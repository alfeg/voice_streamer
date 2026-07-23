import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../backend/api.dart';
import '../backend/modules/chats.dart';
import '../backend/modules/messages.dart';
import '../core/protocol/opcode_map.dart';
import '../core/protocol/packet.dart';
import '../core/storage/app_database.dart';
import '../core/storage/token_storage.dart';
import '../models/attachment.dart';
import 'package:komet/tts/tts_service.dart';
import 'package:komet/reader/channel_config.dart';
import 'package:komet/reader/message_feed.dart';
import 'package:komet/reader/playback_queue.dart';

class ReaderService {
  ReaderService._();

  static final ReaderService instance = ReaderService._();

  static const int _dedupeLimit = 500;
  static const int _maxTtsChars = 150;

  Api? _api;
  PlaybackQueue? _queue;
  TtsService? _tts;
  StreamSubscription<Packet>? _subscription;

  final Queue<String> _seenOrder = Queue<String>();
  final Set<String> _seen = <String>{};

  final ValueNotifier<bool> watching = ValueNotifier<bool>(false);

  void init({
    required Api api,
    required PlaybackQueue queue,
    required TtsService tts,
  }) {
    _api = api;
    _queue = queue;
    _tts = tts;
  }

  void startWatching() {
    final api = _api;
    final queue = _queue;
    if (api == null || queue == null) return;

    _subscription?.cancel();
    _subscription = null;

    queue.setSpeed(ChannelConfig.speed);
    _subscription = api.pushStream.listen(_onPush);
    watching.value = true;
    debugPrint(
      '[READER] watching STARTED reader#${identityHashCode(this)} '
      'api#${identityHashCode(api)} queue#${identityHashCode(queue)} '
      'modes=${ChannelConfig.all}',
    );
    _subscribeWatchedChannels(api);
  }

  Future<void> _subscribeWatchedChannels(Api api) async {
    for (final entry in ChannelConfig.all.entries) {
      if (entry.value == WatchMode.off) continue;
      debugPrint('[READER] chatSubscribe -> ${entry.key}');
      await chats.subscribeChat(api, entry.key, subscribe: true);
    }
  }

  void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    watching.value = false;
    debugPrint('[READER] watching STOPPED');
  }

  Future<void> _onPush(Packet packet) async {
    debugPrint('[READER] reader#${identityHashCode(this)} push opcode=${packet.opcode} (${Opcode.name(packet.opcode)})');
    if (packet.opcode != Opcode.notifMessage) return;

    try {
      final payload = packet.payload;
      if (payload is! Map) {
        debugPrint('[READER] notifMessage: payload not a Map: $payload');
        return;
      }
      final chatId = payload['chatId'];
      final rawMsg = payload['message'];
      debugPrint(
        '[READER] notifMessage chatId=$chatId '
        'msgKeys=${rawMsg is Map ? rawMsg.keys.toList() : rawMsg}',
      );
      if (chatId is! int) {
        debugPrint('[READER] skip: chatId not int ($chatId)');
        return;
      }
      if (rawMsg is! Map) {
        debugPrint('[READER] skip: message not a Map');
        return;
      }

      final mode = ChannelConfig.modeFor(chatId);
      debugPrint('[READER] chat $chatId mode=$mode');
      if (mode == WatchMode.off) {
        debugPrint('[READER] skip: chat $chatId is OFF (not watched)');
        return;
      }

      final msgId = rawMsg['id']?.toString();
      if (msgId == null) {
        debugPrint('[READER] skip: message has no id');
        return;
      }
      if (_alreadySeen(msgId)) {
        debugPrint('[READER] skip: duplicate id=$msgId');
        return;
      }
      _markSeen(msgId);

      final accountId = await TokenStorage.getActiveAccountId();
      if (accountId == null) {
        debugPrint('[READER] skip: no active account');
        return;
      }

      final message = CachedMessage.fromPushPayload(accountId, chatId, rawMsg);
      final attachTypes =
          message.attachments?.map((a) => a.type).toList() ?? const [];
      debugPrint(
        '[READER] msg id=${message.id} text="${message.text}" '
        'attaches=$attachTypes',
      );

      final chat = await _resolveChat(accountId, chatId);
      final title = chat?.title ?? 'Канал $chatId';
      final iconUrl = chat?.iconUrl;

      if (mode == WatchMode.voice || mode == WatchMode.both) {
        await _handleVoice(message, title, iconUrl);
      }

      if (mode == WatchMode.tts || mode == WatchMode.both) {
        await _handleText(message, title, iconUrl);
      }
    } catch (e, st) {
      debugPrint('[READER] push handling failed: $e\n$st');
    }
  }

  Future<CachedChat?> _resolveChat(int accountId, int chatId) async {
    try {
      final rows = await AppDatabase.loadChat(accountId, chatId);
      if (rows.isEmpty) return null;
      return CachedChat.fromDbRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleVoice(
    CachedMessage message,
    String title,
    String? iconUrl,
  ) async {
    final queue = _queue;
    if (queue == null) return;

    final attachments = message.attachments;
    if (attachments == null) {
      debugPrint('[READER] voice: no attachments');
      return;
    }

    for (final att in attachments) {
      if (att is AudioAttachment || att.type == AttachmentType.audio) {
        final url = att.fileUrl ?? att.baseUrl;
        if (url != null && url.isNotEmpty) {
          debugPrint('[READER] ENQUEUE voice url=$url');
          MessageFeed.instance.add(
            FeedItem(
              id: message.id,
              title: title,
              iconUrl: iconUrl,
              text: 'Голосовое сообщение',
              isVoice: true,
              time: DateTime.now(),
            ),
          );
          await queue.enqueueVoiceUrl(
            url,
            title: title,
            subtitle: 'Голосовое сообщение',
            iconUrl: iconUrl,
          );
          return;
        }
        debugPrint('[READER] voice attach has no url: fileUrl=${att.fileUrl} baseUrl=${att.baseUrl}');
      }
    }
    debugPrint('[READER] voice: no AUDIO attachment found');
  }

  Future<void> _handleText(
    CachedMessage message,
    String title,
    String? iconUrl,
  ) async {
    final queue = _queue;
    final tts = _tts;
    if (queue == null || tts == null) return;

    final raw = message.text;
    if (raw == null || raw.trim().isEmpty) {
      debugPrint('[READER] tts: empty text, skip');
      return;
    }
    if (!tts.isReady) {
      debugPrint('[READER] tts: engine NOT ready (model not provisioned), skip');
      return;
    }

    final trimmed = raw.trim();
    final text = trimmed.length > _maxTtsChars
        ? '${trimmed.substring(0, _maxTtsChars)}…'
        : trimmed;
    if (text.length < trimmed.length) {
      debugPrint('[READER] tts: text clipped ${trimmed.length} -> $_maxTtsChars');
    }

    MessageFeed.instance.add(
      FeedItem(
        id: message.id,
        title: title,
        iconUrl: iconUrl,
        text: text,
        isVoice: false,
        time: DateTime.now(),
      ),
    );

    final wav = await tts.synthesizeToWav(text, speed: ChannelConfig.speed);
    if (wav != null) {
      debugPrint('[READER] ENQUEUE tts wav=$wav');
      await queue.enqueueWav(
        wav,
        title: title,
        subtitle: text,
        iconUrl: iconUrl,
      );
    } else {
      debugPrint('[READER] tts: synth returned null');
    }
  }

  bool _alreadySeen(String id) => _seen.contains(id);

  void _markSeen(String id) {
    _seen.add(id);
    _seenOrder.add(id);
    while (_seenOrder.length > _dedupeLimit) {
      _seen.remove(_seenOrder.removeFirst());
    }
  }
}

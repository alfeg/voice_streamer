import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../backend/modules/chats.dart';
import '../backend/modules/messages.dart';
import '../models/attachment.dart';
import '../tts/tts_service.dart';
import 'channel_config.dart';
import 'playback_queue.dart';

class ReaderService {
  ReaderService._();

  static final ReaderService instance = ReaderService._();

  static const int _dedupeLimit = 200;

  PlaybackQueue? _queue;
  TtsService? _tts;
  StreamSubscription<MessageEvent>? _subscription;

  final Queue<String> _seenOrder = Queue<String>();
  final Set<String> _seen = <String>{};

  final ValueNotifier<bool> watching = ValueNotifier<bool>(false);

  void init({required PlaybackQueue queue, required TtsService tts}) {
    _queue = queue;
    _tts = tts;
  }

  void startWatching() {
    if (watching.value) return;
    final queue = _queue;
    if (queue == null) return;

    queue.setSpeed(ChannelConfig.speed);
    _subscription = chats.messageEvents.listen(_onEvent);
    watching.value = true;
  }

  void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    watching.value = false;
  }

  Future<void> _onEvent(MessageEvent event) async {
    if (event is! MessageAddedEvent) return;

    final chatId = event.chatId;
    final message = event.message;

    final mode = ChannelConfig.modeFor(chatId);
    if (mode == WatchMode.off) return;

    if (_alreadySeen(message.id)) return;
    _markSeen(message.id);

    final title = chatId.toString();

    if (mode == WatchMode.voice || mode == WatchMode.both) {
      await _handleVoice(message, title);
    }

    if (mode == WatchMode.tts || mode == WatchMode.both) {
      await _handleText(message, title);
    }
  }

  Future<void> _handleVoice(CachedMessage message, String title) async {
    final queue = _queue;
    if (queue == null) return;

    final attachments = message.attachments;
    if (attachments == null) return;

    for (final att in attachments) {
      if (att is AudioAttachment || att.type == AttachmentType.audio) {
        final url = att.fileUrl ?? att.baseUrl;
        if (url != null && url.isNotEmpty) {
          await queue.enqueueVoiceUrl(
            url,
            title: title,
            subtitle: 'Голосовое сообщение',
          );
          return;
        }
      }
    }
  }

  Future<void> _handleText(CachedMessage message, String title) async {
    final queue = _queue;
    final tts = _tts;
    if (queue == null || tts == null) return;

    final text = message.text;
    if (text == null || text.trim().isEmpty) return;

    final wav = await tts.synthesizeToWav(text, speed: ChannelConfig.speed);
    if (wav != null) {
      await queue.enqueueWav(wav, title: title, subtitle: text);
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

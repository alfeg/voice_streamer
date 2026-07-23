import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/config/komet_settings.dart';
import '../../core/protocol/opcode_map.dart';
import '../../core/protocol/packet.dart';
import '../../core/cache/info_cache.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/text_format.dart';
import '../api.dart';
import 'chat_parsing.dart';
import 'chat_preview.dart';
import 'messages.dart' show CachedMessage;

Map<int, int> parseParticipants(dynamic raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map) {
      return decoded.map(
        (k, v) => MapEntry(
          k is int ? k : int.parse(k.toString()),
          v is int ? v : int.tryParse(v.toString()) ?? 0,
        ),
      );
    }
  } catch (e) {
    logger.e('Failed to parse participants: $e');
  }
  return {};
}

class CachedChat {
  final int id;
  final int accountId;
  final String type;
  final String? title;
  final String? iconUrl;
  final int? lastMsgId;
  final int? lastMsgTime;
  final String? lastMsgText;
  final String? lastMsgTextOneLine;
  final String? lastMsgElements;
  final int? lastMsgSenderId;
  final String? lastMsgStatus;
  final int unreadCount;
  final int lastEventTime;
  final int cachedAt;
  final int? favIndex;
  final int dontDisturbUntil;
  final bool isOnline;
  final int seenTime;
  final Map<int, int> participants;
  final Set<String> options;
  final int? owner;
  final Set<int> admins;
  final int? pinnedMsgId;
  final String? pinnedMsgText;
  final int? pinnedMsgTime;
  final bool pinnedMsgIsPreview;

  CachedChat({
    required this.id,
    required this.accountId,
    required this.type,
    this.title,
    this.iconUrl,
    this.lastMsgId,
    this.lastMsgTime,
    this.lastMsgText,
    this.lastMsgElements,
    this.lastMsgSenderId,
    this.lastMsgStatus,
    required this.unreadCount,
    required this.lastEventTime,
    required this.cachedAt,
    this.favIndex,
    required this.dontDisturbUntil,
    required this.isOnline,
    required this.seenTime,
    required this.participants,
    this.options = const {},
    this.owner,
    this.admins = const {},
    this.pinnedMsgId,
    this.pinnedMsgText,
    this.pinnedMsgTime,
    this.pinnedMsgIsPreview = false,
  }) : lastMsgTextOneLine = lastMsgText != null && lastMsgText.contains('\n')
           ? lastMsgText.replaceAll('\n', ' ')
           : lastMsgText;

  bool get isOfficial => options.contains('OFFICIAL');

  List<FormatRange> get lastMsgFormatRanges {
    final raw = lastMsgElements;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return parseFormatElements(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  bool get lastMsgReadByOthers {
    final t = lastMsgTime;
    if (t == null) return false;
    for (final entry in participants.entries) {
      if (entry.key != accountId && entry.value >= t) return true;
    }
    return false;
  }

  bool iAmAdmin(int myId) => owner == myId || admins.contains(myId);

  bool get hasPinnedMessage => pinnedMsgId != null;

  bool get isGroupChat => type == 'CHAT' || type == 'GROUP';

  bool canPinMessages(int myId) {
    if (!isGroupChat) return false;
    return iAmAdmin(myId) || options.contains('ALL_CAN_PIN_MESSAGE');
  }

  bool get isMuted {
    if (dontDisturbUntil == ChatsModule.muteOff) return false;
    if (dontDisturbUntil < 0) return true;
    return dontDisturbUntil > DateTime.now().millisecondsSinceEpoch;
  }

  bool get isLastMsgDeleted => lastMsgText == ChatsModule.lastMsgPlaceholder;

  factory CachedChat.fromDbRow(Map<String, dynamic> row) => CachedChat(
    id: row['id'] as int,
    accountId: row['account_id'] as int,
    type: row['type'] as String,
    title: row['title'] as String?,
    iconUrl: row['icon_url'] as String?,
    lastMsgId: row['last_msg_id'] as int?,
    lastMsgTime: row['last_msg_time'] as int?,
    lastMsgText: row['last_msg_text'] as String?,
    lastMsgElements: row['last_msg_elements'] as String?,
    lastMsgSenderId: row['last_msg_sender'] as int?,
    lastMsgStatus: row['last_msg_status'] as String?,
    unreadCount: row['unread_count'] as int,
    lastEventTime: row['last_event_time'] as int,
    cachedAt: row['cached_at'] as int,
    favIndex: row['fav_index'] as int?,
    dontDisturbUntil: row['dont_disturb_until'] as int,
    isOnline: (row['is_online'] as int) == 1,
    seenTime: row['seen_time'] as int,
    participants: parseParticipants(row['participants']),
    options: _decodeOptions(row['options']),
    owner: row['owner'] as int?,
    admins: _decodeAdmins(row['admins']),
    pinnedMsgId: row['pinned_msg_id'] as int?,
    pinnedMsgText: row['pinned_msg_text'] as String?,
    pinnedMsgTime: row['pinned_msg_time'] as int?,
    pinnedMsgIsPreview: (row['pinned_msg_is_preview'] as int? ?? 0) == 1,
  );

  static Set<String> _decodeOptions(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const {};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Set<int> _decodeAdmins(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const {};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Map<String, dynamic> toDbRow() => {
    'id': id,
    'account_id': accountId,
    'type': type,
    'title': title,
    'icon_url': iconUrl,
    'last_msg_id': lastMsgId,
    'last_msg_time': lastMsgTime,
    'last_msg_text': lastMsgText,
    'last_msg_elements': lastMsgElements,
    'last_msg_sender': lastMsgSenderId,
    'last_msg_status': lastMsgStatus,
    'unread_count': unreadCount,
    'last_event_time': lastEventTime,
    'cached_at': cachedAt,
    'fav_index': favIndex,
    'dont_disturb_until': dontDisturbUntil,
    'is_online': isOnline ? 1 : 0,
    'seen_time': seenTime,
    'participants': jsonEncode(
      participants.map((k, v) => MapEntry(k.toString(), v)),
    ),
    'options': options.isEmpty ? null : options.join(','),
    'owner': owner,
    'admins': admins.isEmpty ? null : admins.join(','),
    'pinned_msg_id': pinnedMsgId,
    'pinned_msg_text': pinnedMsgText,
    'pinned_msg_time': pinnedMsgTime,
    'pinned_msg_is_preview': pinnedMsgIsPreview ? 1 : 0,
  };

  static const Object _keep = Object();

  CachedChat copyWith({
    String? type,
    Object? title = _keep,
    Object? iconUrl = _keep,
    Object? lastMsgId = _keep,
    Object? lastMsgTime = _keep,
    Object? lastMsgText = _keep,
    Object? lastMsgElements = _keep,
    Object? lastMsgSenderId = _keep,
    Object? lastMsgStatus = _keep,
    int? unreadCount,
    int? lastEventTime,
    int? cachedAt,
    Object? favIndex = _keep,
    int? dontDisturbUntil,
    bool? isOnline,
    int? seenTime,
    Map<int, int>? participants,
    Set<String>? options,
    Object? owner = _keep,
    Set<int>? admins,
    Object? pinnedMsgId = _keep,
    Object? pinnedMsgText = _keep,
    Object? pinnedMsgTime = _keep,
    bool? pinnedMsgIsPreview,
  }) {
    return CachedChat(
      id: id,
      accountId: accountId,
      type: type ?? this.type,
      title: identical(title, _keep) ? this.title : title as String?,
      iconUrl: identical(iconUrl, _keep) ? this.iconUrl : iconUrl as String?,
      lastMsgId: identical(lastMsgId, _keep)
          ? this.lastMsgId
          : lastMsgId as int?,
      lastMsgTime: identical(lastMsgTime, _keep)
          ? this.lastMsgTime
          : lastMsgTime as int?,
      lastMsgText: identical(lastMsgText, _keep)
          ? this.lastMsgText
          : lastMsgText as String?,
      lastMsgElements: identical(lastMsgElements, _keep)
          ? this.lastMsgElements
          : lastMsgElements as String?,
      lastMsgSenderId: identical(lastMsgSenderId, _keep)
          ? this.lastMsgSenderId
          : lastMsgSenderId as int?,
      lastMsgStatus: identical(lastMsgStatus, _keep)
          ? this.lastMsgStatus
          : lastMsgStatus as String?,
      unreadCount: unreadCount ?? this.unreadCount,
      lastEventTime: lastEventTime ?? this.lastEventTime,
      cachedAt: cachedAt ?? this.cachedAt,
      favIndex: identical(favIndex, _keep) ? this.favIndex : favIndex as int?,
      dontDisturbUntil: dontDisturbUntil ?? this.dontDisturbUntil,
      isOnline: isOnline ?? this.isOnline,
      seenTime: seenTime ?? this.seenTime,
      participants: participants ?? this.participants,
      options: options ?? this.options,
      owner: identical(owner, _keep) ? this.owner : owner as int?,
      admins: admins ?? this.admins,
      pinnedMsgId: identical(pinnedMsgId, _keep)
          ? this.pinnedMsgId
          : pinnedMsgId as int?,
      pinnedMsgText: identical(pinnedMsgText, _keep)
          ? this.pinnedMsgText
          : pinnedMsgText as String?,
      pinnedMsgTime: identical(pinnedMsgTime, _keep)
          ? this.pinnedMsgTime
          : pinnedMsgTime as int?,
      pinnedMsgIsPreview: pinnedMsgIsPreview ?? this.pinnedMsgIsPreview,
    );
  }
}

sealed class MessageEvent {
  final int chatId;
  const MessageEvent(this.chatId);
}

class MessageAddedEvent extends MessageEvent {
  final CachedMessage message;
  const MessageAddedEvent(super.chatId, this.message);
}

class MessageEditedEvent extends MessageEvent {
  final CachedMessage message;
  const MessageEditedEvent(super.chatId, this.message);
}

class MessageRemovedEvent extends MessageEvent {
  final String messageId;
  const MessageRemovedEvent(super.chatId, this.messageId);
}

class MessageMarkedDeletedEvent extends MessageEvent {
  final String messageId;
  const MessageMarkedDeletedEvent(super.chatId, this.messageId);
}

class MessageReactionsChangedEvent extends MessageEvent {
  final String messageId;
  final Map<String, dynamic>? reactionInfo;
  const MessageReactionsChangedEvent(
    super.chatId,
    this.messageId,
    this.reactionInfo,
  );
}

class ChatsModule {
  static const int muteOff = 0;
  static const int muteForever = -1;

  /// Sentinel в `lastMsgText` когда последнее сообщение в чате удалено,
  /// а кеша истории нет — UI должен отрисовать курсивную плашку.
  static const String lastMsgPlaceholder = '__komet_lastmsg_placeholder__';

  ChatsModule._();

  final _messageEventsController = StreamController<MessageEvent>.broadcast();
  Stream<MessageEvent> get messageEvents => _messageEventsController.stream;

  int? _paginatedAccountId;

  final ValueNotifier<int> chatsChanged = ValueNotifier(0);
  void _bump() => chatsChanged.value = chatsChanged.value + 1;

  static Map<String, dynamic>? _decodePayload(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return null;
  }

  StreamSubscription<Packet>? _globalPushSub;
  StreamSubscription<SessionState>? _globalStateSub;
  Future<void> _pushQueue = Future.value();

  void attachGlobalPushHandlers(Api api) {
    _globalPushSub?.cancel();
    _globalStateSub?.cancel();
    _globalPushSub = api.pushStream.listen(_enqueueGlobalPush);
    _globalStateSub = api.stateStream.listen(_handleSessionState);
  }

  void dispose() {
    _globalPushSub?.cancel();
    _globalStateSub?.cancel();
    _globalPushSub = null;
    _globalStateSub = null;
    _messageEventsController.close();
    chatsChanged.dispose();
  }

  void _handleSessionState(SessionState state) {
    if (state == SessionState.disconnected) {
      PresenceFetch.clear();
      ChatInfoFetch.clear();
    }
  }

  void resetForAccountSwitch() {
    PresenceFetch.clear();
    ChatInfoFetch.clear();
  }

  void _enqueueGlobalPush(Packet packet) {
    _pushQueue = _pushQueue.then((_) => _handleGlobalPush(packet)).catchError((
      Object e,
    ) {
      logger.w('Ошибка обработки пуша: $e');
    });
  }

  Future<void> _handleGlobalPush(Packet packet) async {
    switch (packet.opcode) {
      case Opcode.notifMessage:
        await _handleNotifMessage(packet);
      case Opcode.notifMark:
        await _handleNotifMark(packet);
      case Opcode.notifMsgReactionsChanged:
        await _handleNotifMsgReactionsChanged(packet);
      case Opcode.notifMsgDelete:
        await _handleNotifMsgDelete(packet);
      case Opcode.notifPresence:
        _handlePresence(packet);
    }
  }

  void _handlePresence(Packet packet) {
    final payload = packet.payload;
    if (payload is! Map) return;
    final userId = payload['userId'];
    if (userId is! int) return;
    final presence = payload['presence'];
    if (presence is! Map) return;
    PresenceFetch.apply(userId, Map<String, dynamic>.from(presence));
  }

  Future<void> _handleNotifMsgDelete(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final chatMap = payload['chat'];
    int? chatId;
    if (chatMap is Map && chatMap['id'] is int) {
      chatId = chatMap['id'] as int;
      await cacheServerChat(chatMap.cast<dynamic, dynamic>(), accountId);
    } else if (payload['chatId'] is int) {
      chatId = payload['chatId'] as int;
    }
    if (chatId == null) return;

    final keepDeleted = KometSettings.viewDeleted.value;
    final ids = payload['messageIds'];
    if (ids is List) {
      for (final raw in ids) {
        final id = raw?.toString();
        if (id == null || id.isEmpty) continue;
        if (keepDeleted) {
          await AppDatabase.markMessageDeleted(accountId, chatId, id);
          _messageEventsController.add(MessageMarkedDeletedEvent(chatId, id));
        } else {
          await AppDatabase.deleteMessage(accountId, chatId, id);
          _messageEventsController.add(MessageRemovedEvent(chatId, id));
        }
      }
    }
    _bump();
  }

  Future<void> _handleNotifMessage(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    if (chatId is! int) return;
    final msg = payload['message'];
    if (msg is! Map) return;

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final senderId = msg['sender'] as int?;
    final msgIdStr = msg['id']?.toString();
    final msgIdInt = (msg['id'] is int)
        ? msg['id'] as int
        : int.tryParse(msgIdStr ?? '');
    final msgTime = msg['time'] as int?;
    final msgText = msg['text'] as String?;
    final status = msg['status'] as String?;
    final unread = payload['unread'] as int?;

    var rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) {
      try {
        final chatInfo = await ChatInfoFetch.get(chatId);
        if (chatInfo != null) {
          await cacheServerChat(chatInfo.raw, accountId);
        }
      } catch (e) {
        logger.w(
          'notifMessage: fetch info for unknown chat $chatId failed: $e',
        );
        return;
      }
      rows = await AppDatabase.loadChat(accountId, chatId);
      if (rows.isEmpty) return;
    }

    if (status == 'REMOVED' && msgIdStr != null) {
      final keepDeleted = KometSettings.viewDeleted.value;
      if (keepDeleted) {
        await AppDatabase.markMessageDeleted(accountId, chatId, msgIdStr);
      } else {
        await AppDatabase.deleteMessage(accountId, chatId, msgIdStr);
      }
      final cachedChat = CachedChat.fromDbRow(rows.first);
      if (cachedChat.lastMsgId == msgIdInt) {
        await _reconcileLastMessage(
          accountId,
          chatId,
          rows.first,
          unread: unread,
        );
      } else if (unread != null) {
        final newRow = Map<String, dynamic>.from(rows.first);
        newRow['unread_count'] = unread;
        await AppDatabase.saveChats([newRow]);
      }
      _messageEventsController.add(
        keepDeleted
            ? MessageMarkedDeletedEvent(chatId, msgIdStr)
            : MessageRemovedEvent(chatId, msgIdStr),
      );
      _bump();
      return;
    }

    CachedMessage? emittedMessage;
    if (status == 'EDITED' && msgIdStr != null) {
      final existing = await AppDatabase.loadMessage(
        accountId,
        chatId,
        msgIdStr,
      );
      if (existing != null) {
        final mergedPayload =
            _decodePayload(existing['payload']) ??
            Map<String, dynamic>.from(msg);
        for (final entry in msg.entries) {
          if (entry.key == 'reactionInfo') continue;
          mergedPayload[entry.key.toString()] = entry.value;
        }
        final newRow = Map<String, dynamic>.from(existing);
        if (KometSettings.viewRedacted.value) {
          final oldText = existing['text']?.toString();
          if ((oldText ?? '') != (msgText ?? '') &&
              oldText != null &&
              oldText.isNotEmpty) {
            final history = CachedMessage.appendEditHistory(
              CachedMessage.parseEditHistory(existing['edit_history']),
              oldText,
              DateTime.now().millisecondsSinceEpoch,
            );
            newRow['edit_history'] = jsonEncode(history);
          }
        }
        newRow['text'] = msgText;
        newRow['status'] = status;
        newRow['payload'] = jsonEncode(mergedPayload);
        await AppDatabase.saveMessages([newRow]);
        emittedMessage = CachedMessage.fromDbRow(newRow);
        _messageEventsController.add(
          MessageEditedEvent(chatId, emittedMessage),
        );
      }
    } else if (msgIdStr != null) {
      final existing = await AppDatabase.loadMessage(
        accountId,
        chatId,
        msgIdStr,
      );
      if (existing == null) {
        final cached = CachedMessage.fromPushPayload(accountId, chatId, msg);
        await AppDatabase.saveMessages([cached.toDbRow()]);
        emittedMessage = cached;
        _messageEventsController.add(MessageAddedEvent(chatId, cached));
      }
    }

    final cached = CachedChat.fromDbRow(rows.first);
    final isStaleLast =
        status != 'REMOVED' &&
        msgIdInt != null &&
        cached.lastMsgId == msgIdInt &&
        status != 'EDITED';
    if (isStaleLast) {
      _bump();
      return;
    }

    final newRow = Map<String, dynamic>.from(rows.first);
    if (status != 'REMOVED') {
      if (msgIdInt != null) newRow['last_msg_id'] = msgIdInt;
      if (msgTime != null) {
        newRow['last_msg_time'] = msgTime;
        if (status != 'EDITED') {
          newRow['last_event_time'] = msgTime;
        }
      }
      newRow['last_msg_text'] = messagePreviewText(msg);
      newRow['last_msg_elements'] = messagePreviewElements(msg);
      if (senderId != null) newRow['last_msg_sender'] = senderId;
      newRow['last_msg_status'] = 'sent';
    }
    if (unread != null) newRow['unread_count'] = unread;

    final pinned = _extractPinnedMessage(msg);
    if (pinned != null) {
      newRow['pinned_msg_id'] = pinned.id;
      newRow['pinned_msg_text'] = pinned.text;
      newRow['pinned_msg_time'] = pinned.time;
      newRow['pinned_msg_is_preview'] = pinned.isPreview ? 1 : 0;
    }

    await AppDatabase.saveChats([newRow]);
    _bump();
  }

  ({int? id, String? text, int? time, bool isPreview})? _extractPinnedMessage(
    Map msg,
  ) {
    final attaches = msg['attaches'];
    if (attaches is! List) return null;
    for (final a in attaches.whereType<Map>()) {
      if ((a['_type'] as String?) != 'CONTROL') continue;
      final event = a['event']?.toString();
      if (event != 'pin' && event != 'unpin') continue;
      final pinned = a['pinnedMessage'];
      if (event == 'unpin' || pinned is! Map) {
        return (id: null, text: null, time: null, isPreview: false);
      }
      final rawId = pinned['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      if (id == null) return null;
      final preview = pinnedMessagePreview(pinned.cast<dynamic, dynamic>());
      return (
        id: id,
        text: preview.text,
        time: pinned['time'] as int?,
        isPreview: preview.isPreview,
      );
    }
    return null;
  }

  Future<void> _reconcileLastMessage(
    int accountId,
    int chatId,
    Map<String, dynamic> chatRow, {
    int? unread,
  }) async {
    final latest = await AppDatabase.loadMessages(
      accountId,
      chatId,
      limit: 1,
      onlyVisible: true,
    );
    final newRow = Map<String, dynamic>.from(chatRow);
    if (latest.isNotEmpty) {
      final m = latest.first;
      final rawText = m['text']?.toString();
      String? previewText = rawText;
      String? elementsJson;
      final payload = _decodePayload(m['payload']);
      if (rawText == null || rawText.isEmpty) {
        if (payload != null) previewText = messagePreviewText(payload);
      } else {
        if (payload != null) elementsJson = messagePreviewElements(payload);
      }
      newRow['last_msg_id'] = int.tryParse(m['id']?.toString() ?? '');
      newRow['last_msg_text'] = previewText ?? m['text'];
      newRow['last_msg_elements'] = elementsJson;
      newRow['last_msg_time'] = m['time'];
      newRow['last_msg_sender'] = m['sender_id'];
      newRow['last_msg_status'] = m['status'];
    } else {
      newRow['last_msg_id'] = null;
      newRow['last_msg_text'] = lastMsgPlaceholder;
      newRow['last_msg_elements'] = null;
      newRow['last_msg_sender'] = null;
      newRow['last_msg_status'] = null;
    }
    if (unread != null) newRow['unread_count'] = unread;
    await AppDatabase.saveChats([newRow]);
  }

  Future<void> _handleNotifMsgReactionsChanged(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    if (chatId is! int) return;
    final messageId = payload['messageId']?.toString();
    if (messageId == null || messageId.isEmpty) return;

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final existing = await AppDatabase.loadMessage(
      accountId,
      chatId,
      messageId,
    );
    if (existing == null) return;

    final payloadMap =
        _decodePayload(existing['payload']) ?? <String, dynamic>{};

    final counters = payload['counters'];
    final totalCount = payload['totalCount'];
    final reactionInfo = <String, dynamic>{};
    final prev = payloadMap['reactionInfo'];
    if (prev is Map && prev['yourReaction'] != null) {
      reactionInfo['yourReaction'] = prev['yourReaction'];
    }
    if (counters is List) reactionInfo['counters'] = counters;
    if (totalCount is int) reactionInfo['totalCount'] = totalCount;
    if (reactionInfo['counters'] == null ||
        (counters is List && counters.isEmpty)) {
      payloadMap.remove('reactionInfo');
    } else {
      payloadMap['reactionInfo'] = reactionInfo;
    }

    final newRow = Map<String, dynamic>.from(existing);
    newRow['payload'] = jsonEncode(payloadMap);
    await AppDatabase.saveMessages([newRow]);
    final emitted = payloadMap['reactionInfo'] as Map<String, dynamic>?;
    _messageEventsController.add(
      MessageReactionsChangedEvent(chatId, messageId, emitted),
    );
    _bump();
  }

  Future<void> _handleNotifMark(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    if (chatId is! int) return;
    final userId = payload['userId'];
    if (userId is! int) return;
    final mark = payload['mark'];
    if (mark is! int) return;
    if (payload['setAsUnread'] == true) return;

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    final cached = CachedChat.fromDbRow(rows.first);
    if (cached.participants[userId] == mark) return;
    cached.participants[userId] = mark;
    await AppDatabase.saveChats([cached.toDbRow()]);
    _bump();
  }

  Future<CachedChat?> cacheServerChat(
    Map<dynamic, dynamic> chat,
    int accountId, {
    Map<int, CachedChat>? preloadedExisting,
    bool inList = true,
  }) async {
    final cachedAt = DateTime.now().millisecondsSinceEpoch;
    final id = chat['id'];
    Map<int, CachedChat> existing = const {};
    if (preloadedExisting != null) {
      existing = preloadedExisting;
    } else if (id is int) {
      final rows = await AppDatabase.loadChat(accountId, id);
      if (rows.isNotEmpty) {
        existing = {id: CachedChat.fromDbRow(rows.first)};
      }
    }
    final parsed = parseChatRow(
      chat,
      accountId,
      accountId,
      const {},
      const {},
      const {},
      existing,
      cachedAt,
    );
    if (parsed == null) {
      logger.w('cacheServerChat: parse returned null for chat=${chat['id']}');
      return null;
    }
    final ex = existing[parsed.id];
    if (ex != null && sameChatContent(ex, parsed)) {
      return parsed;
    }
    final row = parsed.toDbRow();
    row['in_list'] = !inList ? 0 : (chat['status'] == 'HIDDEN' ? 2 : 1);
    await AppDatabase.saveChats([row]);
    _bump();
    return parsed;
  }

  /// Парсит и кэширует чаты из payload opcode 19.
  ///
  /// Для диалогов разрезолвит имя и аватар из списка [contacts] того же
  /// ответа. На warm start контакты не приходят — используется существующий
  /// кэш.
  Future<void> syncFromLoginPayload(
    Map<dynamic, dynamic> data,
    int accountId,
    int currentUserId,
  ) async {
    try {
      final chats = data['chats'];
      if (chats is! List || chats.isEmpty) return;

      final contactsMap = buildContactsMap(data['contacts']);
      // Config contains mute setup and fav indexes: config -> chats -> id
      final configMap = data['config'] is Map ? data['config'] as Map : {};
      final chatsConfig = configMap['chats'] is Map
          ? configMap['chats'] as Map
          : {};

      // Presence for online statuses
      final presenceMap = data['presence'] is Map
          ? data['presence'] as Map
          : {};
      PresenceFetch.primeAll(presenceMap);

      await _persistChatMaps(
        chats,
        accountId,
        currentUserId,
        contactsMap: contactsMap,
        chatsConfig: chatsConfig,
        presenceMap: presenceMap,
      );
    } catch (e) {
      logger.e("Ошибка при синке: $e");
    }
  }

  Future<int> _persistChatMaps(
    List<dynamic> chats,
    int accountId,
    int currentUserId, {
    Map<int, Map<dynamic, dynamic>> contactsMap = const {},
    Map<dynamic, dynamic> chatsConfig = const {},
    Map<dynamic, dynamic> presenceMap = const {},
  }) async {
    final cachedAt = DateTime.now().millisecondsSinceEpoch;
    final existingRows = await AppDatabase.loadChats(
      accountId,
      includeHidden: true,
    );
    final existing = {
      for (final row in existingRows)
        row['id'] as int: CachedChat.fromDbRow(row),
    };

    final rows = <Map<String, dynamic>>[];
    for (final c in chats.whereType<Map>()) {
      final map = c.cast<dynamic, dynamic>();
      final parsed = parseChatRow(
        map,
        accountId,
        currentUserId,
        contactsMap,
        chatsConfig,
        presenceMap,
        existing,
        cachedAt,
      );
      if (parsed == null) continue;
      final row = parsed.toDbRow();
      row['in_list'] = map['status'] == 'HIDDEN' ? 2 : 1;
      rows.add(row);
    }

    if (rows.isNotEmpty) {
      await AppDatabase.saveChats(rows);
      _bump();
    }
    return rows.length;
  }

  Future<void> paginateChats(
    Api api,
    int accountId,
    int currentUserId,
    Map<dynamic, dynamic> loginData,
  ) async {
    if (_paginatedAccountId == accountId) return;
    _paginatedAccountId = accountId;
    try {
      var marker = loginData['chatMarker'];
      if (marker is! int || marker <= 0) return;

      const count = 50;
      var page = 0;
      while (page < 200) {
        page++;
        final resp = await api.sendRequestMap(Opcode.chatsList, {
          'marker': marker,
          'count': count,
        });
        if (resp == null) break;
        final chats = resp['chats'];
        if (chats is! List || chats.isEmpty) break;

        await _persistChatMaps(chats, accountId, currentUserId);

        final next = resp['marker'];
        if (next is! int || next == marker || chats.length < count) break;
        marker = next;
      }
    } catch (e) {
      _paginatedAccountId = null;
      logger.w('Пагинация чатов: $e');
    }
  }

  Future<void> subscribeChat(
    Api api,
    int chatId, {
    bool subscribe = true,
  }) async {
    try {
      await api.sendRequest(Opcode.chatSubscribe, {
        'chatId': chatId,
        'subscribe': subscribe,
      });
    } catch (e) {
      logger.w('subscribeChat failed: $e');
    }
  }

}

final chats = ChatsModule._();

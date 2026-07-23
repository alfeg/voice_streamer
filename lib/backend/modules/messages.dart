import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/text_format.dart';
import '../../models/attachment.dart';

class ContactCache {
  static final Map<int, String> _nameCache = {};
  static final Map<int, String> _avatarCache = {};
  static final Map<int, Set<String>> _optionsCache = {};

  static const _prefsKey = 'contact_cache_v1';
  static Timer? _saveTimer;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        final id = int.tryParse(key.toString());
        if (id == null || value is! Map) return;
        final name = value['n'];
        final avatar = value['a'];
        final opts = value['o'];
        if (name is String) _nameCache[id] = name;
        if (avatar is String) _avatarCache[id] = avatar;
        if (opts is List) _optionsCache[id] = opts.whereType<String>().toSet();
      });
    } catch (_) {}
  }

  static void put(int id, String name) {
    _nameCache[id] = name;
    _scheduleSave();
  }

  static void putAvatar(int id, String? baseUrl) {
    if (baseUrl != null) {
      _avatarCache[id] = baseUrl;
      _scheduleSave();
    }
  }

  static void putOptions(int id, Set<String> opts) {
    _optionsCache[id] = opts;
    _scheduleSave();
  }

  static String? get(int id) => _nameCache[id];
  static String? getAvatar(int id) => _avatarCache[id];
  static Set<String>? getOptions(int id) => _optionsCache[id];
  static bool isOfficial(int id) =>
      _optionsCache[id]?.contains('OFFICIAL') ?? false;

  static void clear() {
    _nameCache.clear();
    _avatarCache.clear();
    _optionsCache.clear();
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_wipePersisted());
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () => unawaited(_save()));
  }

  static Future<void> _save() async {
    final ids = <int>{
      ..._nameCache.keys,
      ..._avatarCache.keys,
      ..._optionsCache.keys,
    };
    final map = <String, dynamic>{};
    for (final id in ids) {
      final entry = <String, dynamic>{};
      final name = _nameCache[id];
      final avatar = _avatarCache[id];
      final opts = _optionsCache[id];
      if (name != null) entry['n'] = name;
      if (avatar != null) entry['a'] = avatar;
      if (opts != null && opts.isNotEmpty) entry['o'] = opts.toList();
      if (entry.isNotEmpty) map['$id'] = entry;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  static Future<void> _wipePersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

class ReplyInfo {
  final String? messageId;
  final int senderId;
  final String? text;
  final int? time;
  final List<MessageAttachment>? attachments;

  const ReplyInfo({
    this.messageId,
    required this.senderId,
    this.text,
    this.time,
    this.attachments,
  });

  static ReplyInfo? fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final link = payload['link'];
    if (link is! Map) return null;
    if ((link['type'] as String?)?.toUpperCase() != 'REPLY') return null;

    final msg = link['message'];
    if (msg is! Map) {
      final mid = link['messageId'];
      if (mid == null) return null;
      return ReplyInfo(messageId: mid.toString(), senderId: 0);
    }

    List<MessageAttachment>? attaches;
    final raw = msg['attaches'];
    if (raw is List && raw.isNotEmpty) {
      attaches = raw
          .whereType<Map>()
          .map((a) => MessageAttachment.fromMap(Map<String, dynamic>.from(a)))
          .toList();
    }

    final sender = msg['sender'];
    return ReplyInfo(
      messageId: msg['id']?.toString(),
      senderId: sender is int
          ? sender
          : int.tryParse(sender?.toString() ?? '') ?? 0,
      text: msg['text']?.toString(),
      time: msg['time'] is int ? msg['time'] as int : null,
      attachments: attaches,
    );
  }

  String previewText() {
    final t = text;
    if (t != null && t.trim().isNotEmpty) return t;
    final a = attachments;
    if (a != null && a.isNotEmpty) {
      switch (a.first.type) {
        case AttachmentType.photo:
          return 'Фото';
        case AttachmentType.video:
          return 'Видео';
        case AttachmentType.audio:
          return 'Голосовое сообщение';
        case AttachmentType.file:
          return 'Файл';
        case AttachmentType.sticker:
          return 'Стикер';
        case AttachmentType.contact:
          return 'Контакт';
        case AttachmentType.location:
          return 'Геолокация';
        case AttachmentType.poll:
          return 'Опрос';
        case AttachmentType.call:
          return 'Звонок';
        case AttachmentType.share:
          return 'Ссылка';
        case AttachmentType.control:
          return '';
        case AttachmentType.inlineKeyboard:
          return '';
        case AttachmentType.forward:
          return 'Переслано';
        case AttachmentType.unknown:
          return 'Вложение';
      }
    }
    return '';
  }
}

class CachedMessage {
  final String id;
  final int accountId;
  final int chatId;
  final int senderId;
  final String? text;
  final int time;
  final String? status;
  final Map<String, dynamic>? payload;
  final List<MessageAttachment>? attachments;
  final bool isControl;
  final bool deleted;
  final List<Map<String, dynamic>>? editHistory;

  const CachedMessage({
    required this.id,
    required this.accountId,
    required this.chatId,
    required this.senderId,
    this.text,
    required this.time,
    this.status,
    this.payload,
    this.attachments,
    this.isControl = false,
    this.deleted = false,
    this.editHistory,
  });

  CachedMessage copyWith({
    String? status,
    bool? deleted,
    List<MessageAttachment>? attachments,
    List<Map<String, dynamic>>? editHistory,
    Map<String, dynamic>? payload,
  }) => CachedMessage(
    id: id,
    accountId: accountId,
    chatId: chatId,
    senderId: senderId,
    text: text,
    time: time,
    status: status ?? this.status,
    payload: payload ?? this.payload,
    attachments: attachments ?? this.attachments,
    isControl: isControl,
    deleted: deleted ?? this.deleted,
    editHistory: editHistory ?? this.editHistory,
  );

  static List<Map<String, dynamic>>? parseEditHistory(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        return list.isEmpty ? null : list;
      }
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> appendEditHistory(
    List<Map<String, dynamic>>? current,
    String? oldText,
    int time,
  ) {
    final list = current != null
        ? List<Map<String, dynamic>>.from(current)
        : <Map<String, dynamic>>[];
    if (list.isNotEmpty && (list.last['text'] as String?) == oldText) {
      return list;
    }
    list.add({'text': oldText, 'time': time});
    return list;
  }

  static (List<MessageAttachment>?, bool) parseAttachments(
    Map<String, dynamic> map,
  ) {
    List<MessageAttachment>? attachments;
    final link = map['link'];
    final linkType = link is Map ? link['type'] as String? : null;
    if (linkType == 'FORWARD') {
      attachments = [ForwardedMessageAttachment.fromMap(map)];
    } else {
      final attaches = map['attaches'] as List?;
      if (attaches != null) {
        attachments = attaches
            .whereType<Map>()
            .map((a) => MessageAttachment.fromMap(Map<String, dynamic>.from(a)))
            .toList();
      }
    }
    final isControl =
        attachments?.any((a) => a.type == AttachmentType.control) ?? false;
    return (attachments, isControl);
  }

  factory CachedMessage.fromDbRow(Map<String, dynamic> row) {
    Map<String, dynamic>? payload;
    final payloadRaw = row['payload'];
    if (payloadRaw is String && payloadRaw.isNotEmpty) {
      try {
        payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
      } catch (_) {}
    }

    List<MessageAttachment>? attachments;
    bool isControl = false;
    if (payload != null) {
      final parsed = parseAttachments(payload);
      attachments = parsed.$1;
      isControl = parsed.$2;
    }

    return CachedMessage(
      id: row['id']?.toString() ?? '',
      accountId: row['account_id'] is int
          ? row['account_id'] as int
          : int.tryParse(row['account_id']?.toString() ?? '') ?? 0,
      chatId: row['chat_id'] is int
          ? row['chat_id'] as int
          : int.tryParse(row['chat_id']?.toString() ?? '') ?? 0,
      senderId: row['sender_id'] is int
          ? row['sender_id'] as int
          : int.tryParse(row['sender_id']?.toString() ?? '') ?? 0,
      text: row['text']?.toString(),
      time: row['time'] is int
          ? row['time'] as int
          : int.tryParse(row['time']?.toString() ?? '') ?? 0,
      status: row['status']?.toString(),
      payload: payload,
      attachments: attachments,
      isControl: isControl,
      deleted: row['deleted'] is int
          ? row['deleted'] == 1
          : row['deleted']?.toString() == '1',
      editHistory: parseEditHistory(row['edit_history']),
    );
  }

  int? get delayedTimeToFire {
    final attrs = payload?['delayedAttributes'];
    if (attrs is Map) {
      final t = attrs['timeToFire'];
      if (t is int) return t;
      if (t is String) return int.tryParse(t);
    }
    return null;
  }

  bool get isDelayed => delayedTimeToFire != null;

  ReplyInfo? get replyInfo => ReplyInfo.fromPayload(payload);

  List<FormatRange> get formatRanges =>
      parseFormatElements(payload?['elements']);

  static List<CachedMessage> _decodeRows(List<Map<String, dynamic>> rows) =>
      rows.map(CachedMessage.fromDbRow).toList();

  static Future<List<CachedMessage>> fromDbRowsAsync(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.length < 20) {
      return Future.value(_decodeRows(rows));
    }
    return compute(_decodeRows, rows);
  }

  Map<String, dynamic> toDbRow() => {
    'id': id,
    'account_id': accountId,
    'chat_id': chatId,
    'sender_id': senderId,
    'text': text,
    'time': time,
    'status': status,
    'payload': payload != null ? jsonEncode(payload) : null,
    'deleted': deleted ? 1 : 0,
    'edit_history': editHistory != null ? jsonEncode(editHistory) : null,
  };

  static CachedMessage fromPushPayload(int accountId, int chatId, Map msg) {
    final full = Map<String, dynamic>.from(msg);
    final parsed = parseAttachments(full);
    return CachedMessage(
      id: msg['id']?.toString() ?? '',
      accountId: accountId,
      chatId: chatId,
      senderId: msg['sender'] as int? ?? 0,
      text: msg['text'] as String?,
      time: (msg['time'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      status: (msg['status'] as String?) ?? 'sent',
      payload: full,
      attachments: parsed.$1,
      isControl: parsed.$2,
    );
  }
}

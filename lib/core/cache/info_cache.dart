import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend/api.dart';
import '../../models/chat_info.dart';
import '../protocol/opcode_map.dart';

Api? _api;

void attachInfoCacheApi(Api api) {
  _api = api;
}

class _Entry<T> {
  T? value;
  DateTime? fetchedAt;
  DateTime? failedAt;
  Future<T?>? inFlight;
}

class InfoCache<T> {
  final Duration ttl;
  final Duration failureBackoff;
  final Future<T?> Function(int id) fetcher;
  final Map<int, _Entry<T>> _entries = {};

  InfoCache({
    required this.ttl,
    required this.fetcher,
    this.failureBackoff = const Duration(seconds: 10),
  });

  bool _isFresh(_Entry<T> e) {
    if (e.fetchedAt == null) return false;
    return DateTime.now().difference(e.fetchedAt!) < ttl;
  }

  bool _isInFailureBackoff(_Entry<T> e) {
    if (e.failedAt == null) return false;
    return DateTime.now().difference(e.failedAt!) < failureBackoff;
  }

  Future<T?> get(int id, {bool forceRefresh = false}) {
    final entry = _entries.putIfAbsent(id, () => _Entry<T>());

    if (!forceRefresh && _isFresh(entry)) {
      return Future.value(entry.value);
    }
    if (!forceRefresh && _isInFailureBackoff(entry)) {
      return Future.value(null);
    }
    if (entry.inFlight != null) return entry.inFlight!;

    final future = _runFetch(entry, id);
    entry.inFlight = future;
    return future;
  }

  Future<T?> _runFetch(_Entry<T> entry, int id) async {
    try {
      final result = await fetcher(id);
      entry.value = result;
      entry.fetchedAt = DateTime.now();
      entry.failedAt = null;
      return result;
    } catch (_) {
      entry.failedAt = DateTime.now();
      return null;
    } finally {
      entry.inFlight = null;
    }
  }

  T? peek(int id) {
    final entry = _entries[id];
    if (entry == null || !_isFresh(entry)) return null;
    return entry.value;
  }

  void invalidate(int id) => _entries.remove(id);
  void clear() => _entries.clear();
}

/// Локальное (только из пушей и login-payload) хранилище присутствия.
/// Ничего не запрашивает у сервера.
class PresenceFetch {
  static final Map<int, Map<String, dynamic>> _live = {};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, dynamic>? live(int id) => _live[id];

  static void apply(int id, Map<String, dynamic> presence) {
    if (id <= 0) return;
    _live[id] = presence;
    revision.value++;
  }

  static void clear() {
    _live.clear();
    revision.value++;
  }

  static void primeAll(Map<dynamic, dynamic> presence) {
    presence.forEach((key, value) {
      if (value is! Map) return;
      final id = key is int ? key : int.tryParse(key.toString());
      if (id == null) return;
      _live[id] = Map<String, dynamic>.from(value);
    });
    revision.value++;
  }
}

class ChatInfoFetch {
  static final _cache = InfoCache<ChatInfo>(
    ttl: const Duration(minutes: 5),
    fetcher: _fetch,
  );

  static Future<ChatInfo?> get(int id, {bool forceRefresh = false}) =>
      _cache.get(id, forceRefresh: forceRefresh);

  static ChatInfo? peek(int id) => _cache.peek(id);

  static void invalidate(int id) => _cache.invalidate(id);
  static void clear() => _cache.clear();

  static Future<ChatInfo?> _fetch(int id) async {
    final api = _api;
    if (api == null || api.state != SessionState.online) return null;
    final resp = await api.sendRequest(Opcode.chatInfo, {
      'chatIds': [id],
    });
    final data = resp.payload;
    if (data is! Map) return null;
    final chats = data['chats'];
    if (chats is! List || chats.isEmpty) return null;
    final first = chats.first;
    if (first is! Map) return null;
    return ChatInfo.fromMap(Map<String, dynamic>.from(first));
  }
}

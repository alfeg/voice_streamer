import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WatchMode { off, voice, tts, both }

class ChannelConfig {
  ChannelConfig._();

  static const String _modesKey = 'reader_channel_modes';
  static const String _speedKey = 'reader_speed';

  static final Map<int, WatchMode> _modes = {};
  static double _speed = 1.0;
  static bool _loaded = false;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _modes.clear();
    final raw = prefs.getString(_modesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final chatId = int.tryParse(key.toString());
            final mode = _modeFromName(value?.toString());
            if (chatId != null && mode != null) {
              _modes[chatId] = mode;
            }
          });
        }
      } catch (_) {}
    }

    _speed = _clampSpeed(prefs.getDouble(_speedKey) ?? 1.0);
    _loaded = true;
    _bump();
  }

  static Map<int, WatchMode> get all => Map.unmodifiable(_modes);

  static WatchMode modeFor(int chatId) => _modes[chatId] ?? WatchMode.off;

  static Future<void> setMode(int chatId, WatchMode mode) async {
    if (mode == WatchMode.off) {
      _modes.remove(chatId);
    } else {
      _modes[chatId] = mode;
    }
    await _persistModes();
    _bump();
  }

  static double get speed => _speed;

  static Future<void> setSpeed(double v) async {
    _speed = _clampSpeed(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedKey, _speed);
    _bump();
  }

  static bool get isLoaded => _loaded;

  static Future<void> _persistModes() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, String>{
      for (final entry in _modes.entries) entry.key.toString(): entry.value.name,
    };
    await prefs.setString(_modesKey, jsonEncode(map));
  }

  static double _clampSpeed(double v) => v.clamp(0.5, 2.0).toDouble();

  static WatchMode? _modeFromName(String? name) {
    for (final mode in WatchMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }

  static void _bump() => revision.value = revision.value + 1;
}

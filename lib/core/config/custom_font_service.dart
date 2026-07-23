import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomFontService {
  static const String prefKey = 'app_custom_fonts';

  static final Set<String> _loaded = <String>{};

  static Future<List<String>> families() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefKey) ?? const <String>[];
  }

  static Future<void> preloadCached() async {
    final dir = await _cacheDir();
    for (final family in await families()) {
      if (_loaded.contains(family)) continue;
      final file = _fileFor(dir, family);
      if (!await file.exists()) continue;
      try {
        await _register(family, await file.readAsBytes());
      } catch (_) {}
    }
  }

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/custom_fonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static File _fileFor(Directory dir, String family) {
    final safe = family.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.ttf');
  }

  static Future<void> _register(String family, Uint8List bytes) async {
    if (!_isSfnt(bytes)) {
      throw const FormatException('cached data is not a ttf/otf font');
    }
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(family);
  }

  static bool _isSfnt(Uint8List b) {
    if (b.length < 4) return false;
    final tag = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    return tag == 0x00010000 ||
        tag == 0x4F54544F ||
        tag == 0x74727565 ||
        tag == 0x74746366;
  }
}

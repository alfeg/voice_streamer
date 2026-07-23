import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/utils/logger.dart';

class TtsVoice {
  final String id;
  final String name;
  const TtsVoice(this.id, this.name);
}

class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  static const List<TtsVoice> voices = [
    TtsVoice('vits-piper-ru_RU-irina-medium', 'Ирина (жен.)'),
    TtsVoice('vits-piper-ru_RU-denis-medium', 'Денис (муж.)'),
    TtsVoice('vits-piper-ru_RU-dmitri-medium', 'Дмитрий (муж.)'),
    TtsVoice('vits-piper-ru_RU-ruslan-medium', 'Руслан (муж.)'),
  ];

  static const String _bundledVoice = 'vits-piper-ru_RU-irina-medium';
  static const String _prefKey = 'tts_voice';
  static const String _releaseBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  String voiceId = _bundledVoice;
  final ValueNotifier<String> currentVoice = ValueNotifier<String>(_bundledVoice);

  sherpa.OfflineTts? _tts;
  String? _supportPath;
  bool _ready = false;
  bool _initStarted = false;
  static bool _bindingsInitialized = false;
  static int _fileCounter = 0;

  bool get isReady => _ready;

  Future<String> _support() async =>
      _supportPath ??= (await getApplicationSupportDirectory()).path;

  Directory _voiceDir(String base, String id) => Directory('$base/tts/$id');

  Future<bool> isInstalled(String id) async {
    final base = await _support();
    return File('${_voiceDir(base, id).path}/model.onnx').existsSync();
  }

  Future<bool> init() async {
    if (_initStarted) return _ready;
    _initStarted = true;

    final prefs = await SharedPreferences.getInstance();
    voiceId = prefs.getString(_prefKey) ?? _bundledVoice;
    currentVoice.value = voiceId;

    if (!await isInstalled(voiceId)) {
      await _provisionFromAsset(voiceId);
    }
    if (!await isInstalled(voiceId) && voiceId != _bundledVoice) {
      // selected voice missing and not bundled — fall back to bundled
      voiceId = _bundledVoice;
      currentVoice.value = voiceId;
      if (!await isInstalled(voiceId)) await _provisionFromAsset(voiceId);
    }

    return _buildEngine();
  }

  Future<bool> _buildEngine() async {
    try {
      final base = await _support();
      final dir = _voiceDir(base, voiceId);
      final modelFile = File('${dir.path}/model.onnx');
      final tokensFile = File('${dir.path}/tokens.txt');
      final dataDir = Directory('${dir.path}/espeak-ng-data');

      if (!modelFile.existsSync()) {
        _ready = false;
        logger.w('TtsService: model not installed for $voiceId at ${dir.path}');
        return false;
      }

      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }

      final old = _tts;
      final config = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: modelFile.path,
            tokens: tokensFile.path,
            dataDir: dataDir.existsSync() ? dataDir.path : '',
          ),
          numThreads: 1,
          debug: false,
        ),
      );
      _tts = sherpa.OfflineTts(config);
      _ready = true;
      try {
        old?.free();
      } catch (_) {}
      logger.i('TtsService: ready with voice $voiceId');
      return true;
    } catch (e, st) {
      _ready = false;
      logger.e('TtsService: buildEngine failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Switch to [id], downloading it first if not installed.
  /// [onProgress] receives download fraction (0..1) or null while extracting.
  Future<bool> setVoice(String id, {void Function(double?)? onProgress}) async {
    if (!await isInstalled(id)) {
      final ok = await provisionVoice(id, onProgress: onProgress);
      if (!ok) return false;
    }
    voiceId = id;
    currentVoice.value = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, id);
    return _buildEngine();
  }

  Future<bool> provisionVoice(
    String id, {
    void Function(double?)? onProgress,
  }) async {
    if (await _provisionFromAsset(id)) return true;
    return _downloadAndExtract(id, onProgress: onProgress);
  }

  Future<bool> _provisionFromAsset(String id) async {
    final base = await _support();
    final dir = _voiceDir(base, id);
    try {
      final data = await rootBundle.load('assets/tts/$id.zip');
      final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());
      await _writeArchive(archive, dir);
      logger.i('TtsService: provisioned $id from bundled asset');
      return await isInstalled(id);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _downloadAndExtract(
    String id, {
    void Function(double?)? onProgress,
  }) async {
    final base = await _support();
    final dir = _voiceDir(base, id);
    final url = '$_releaseBase/$id.tar.bz2';
    final client = HttpClient();
    try {
      logger.i('TtsService: downloading $url');
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        logger.w('TtsService: download $id failed HTTP ${resp.statusCode}');
        return false;
      }
      final total = resp.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in resp) {
        builder.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      onProgress?.call(null);

      final tar = BZip2Decoder().decodeBytes(builder.takeBytes());
      final archive = TarDecoder().decodeBytes(tar);
      // entries are prefixed with "<id>/"; strip it so files land in dir
      await _writeArchive(archive, dir, stripPrefix: '$id/');
      await _ensureModelOnnx(dir);
      logger.i('TtsService: downloaded + extracted $id');
      return await isInstalled(id);
    } catch (e, st) {
      logger.e('TtsService: download $id failed', error: e, stackTrace: st);
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _writeArchive(
    Archive archive,
    Directory dir, {
    String? stripPrefix,
  }) async {
    await dir.create(recursive: true);
    for (final entry in archive) {
      var name = entry.name;
      if (stripPrefix != null && name.startsWith(stripPrefix)) {
        name = name.substring(stripPrefix.length);
      }
      if (name.isEmpty) continue;
      final outPath = '${dir.path}/$name';
      if (entry.isFile) {
        final file = File(outPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  Future<void> _ensureModelOnnx(Directory dir) async {
    final model = File('${dir.path}/model.onnx');
    if (model.existsSync()) return;
    final onnx = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.onnx'))
        .toList();
    if (onnx.isNotEmpty) {
      await onnx.first.rename(model.path);
    }
  }

  Future<String?> synthesizeToWav(String text, {double speed = 1.0}) async {
    final engine = _tts;
    if (!_ready || engine == null) return null;

    try {
      final audio = engine.generate(text: text, sid: 0, speed: speed);
      if (audio.samples.isEmpty || audio.sampleRate <= 0) return null;

      final tempDir = Directory.systemTemp;
      final path = '${tempDir.path}/komet_tts_${_fileCounter++}.wav';
      final file = File(path);
      await file.writeAsBytes(
        _encodeWav(audio.samples, audio.sampleRate),
        flush: true,
      );
      return path;
    } catch (e, st) {
      logger.e('TtsService: synthesize failed', error: e, stackTrace: st);
      return null;
    }
  }

  // Lead-in of quiet noise instead of pure silence: idle car Bluetooth sinks
  // need an audible signal to wake up, and pure silence gets swallowed along
  // with the first word.
  static const int _leadNoiseMs = 450;
  static const double _leadNoiseAmplitude = 0.005; // ~-46 dBFS, faint hiss

  Uint8List _encodeWav(Float32List samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final padSamples = (sampleRate * _leadNoiseMs / 1000).round();
    final dataSize = (padSamples + samples.length) * 2;
    final totalSize = 44 + dataSize;

    final bytes = Uint8List(totalSize);
    final view = ByteData.view(bytes.buffer);

    _writeAscii(bytes, 0, 'RIFF');
    view.setUint32(4, totalSize - 8, Endian.little);
    _writeAscii(bytes, 8, 'WAVE');
    _writeAscii(bytes, 12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);
    _writeAscii(bytes, 36, 'data');
    view.setUint32(40, dataSize, Endian.little);

    // Deterministic white noise via a simple LCG (fixed seed) so every
    // generated WAV has an identical lead-in.
    var offset = 44;
    var lcg = 0x2F6E2B1;
    for (var i = 0; i < padSamples; i++) {
      lcg = (lcg * 1103515245 + 12345) & 0x7FFFFFFF;
      final noise = (lcg / 0x7FFFFFFF) * 2.0 - 1.0; // -1..1
      view.setInt16(
        offset,
        (noise * _leadNoiseAmplitude * 32767.0).round(),
        Endian.little,
      );
      offset += 2;
    }
    for (final sample in samples) {
      var value = (sample * 32767.0).round();
      if (value > 32767) value = 32767;
      if (value < -32768) value = -32768;
      view.setInt16(offset, value, Endian.little);
      offset += 2;
    }

    return bytes;
  }

  void _writeAscii(Uint8List bytes, int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }
}

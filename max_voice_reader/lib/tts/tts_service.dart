import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/utils/logger.dart';

class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  static bool _bindingsInitialized = false;

  String voiceId = 'vits-piper-ru_RU-irina-medium';

  sherpa.OfflineTts? _tts;
  bool _ready = false;
  bool _initStarted = false;
  static int _fileCounter = 0;

  bool get isReady => _ready;

  Future<bool> init() async {
    if (_initStarted) return _ready;
    _initStarted = true;

    try {
      final supportDir = await getApplicationSupportDirectory();
      final voiceDir = Directory('${supportDir.path}/tts/$voiceId');
      final modelFile = File('${voiceDir.path}/model.onnx');
      final tokensFile = File('${voiceDir.path}/tokens.txt');
      final dataDir = Directory('${voiceDir.path}/espeak-ng-data');

      if (!modelFile.existsSync()) {
        await _provisionFromAsset(voiceDir);
      }

      if (!modelFile.existsSync()) {
        _ready = false;
        logger.w(
          'TtsService: model not provisioned. Expected model.onnx at '
          '${modelFile.path}. Bundle assets/tts/$voiceId.zip '
          '(scripts/fetch_tts_model.ps1) to enable TTS.',
        );
        return false;
      }

      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }

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
      logger.i('TtsService: ready with voice $voiceId');
      return true;
    } catch (e, st) {
      _ready = false;
      logger.e('TtsService: init failed', error: e, stackTrace: st);
      return false;
    }
  }

  Future<void> _provisionFromAsset(Directory voiceDir) async {
    final assetKey = 'assets/tts/$voiceId.zip';
    try {
      final data = await rootBundle.load(assetKey);
      final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());
      await voiceDir.create(recursive: true);
      for (final entry in archive) {
        final outPath = '${voiceDir.path}/${entry.name}';
        if (entry.isFile) {
          final file = File(outPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      logger.i('TtsService: provisioned model from $assetKey to ${voiceDir.path}');
    } catch (e) {
      logger.w('TtsService: bundled model asset $assetKey unavailable: $e');
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

  Uint8List _encodeWav(Float32List samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = samples.length * 2;
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

    var offset = 44;
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

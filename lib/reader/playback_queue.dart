import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/utils/logger.dart';

class PlayItem {
  final String title;
  final String subtitle;
  final bool isVoice;
  final String source;
  final String? iconUrl;

  const PlayItem({
    required this.title,
    required this.subtitle,
    required this.isVoice,
    required this.source,
    this.iconUrl,
  });
}

class PlaybackQueue {
  PlaybackQueue._();

  static final PlaybackQueue instance = PlaybackQueue._();

  static const Duration _idleResetDelay = Duration(seconds: 3);

  AudioPlayer? _player;
  final Queue<PlayItem> _pending = Queue<PlayItem>();
  bool _pumping = false;
  double _speed = 1.0;
  Timer? _idleTimer;

  final ValueNotifier<PlayItem?> current = ValueNotifier<PlayItem?>(null);
  final ValueNotifier<int> queueLength = ValueNotifier<int>(0);

  Future<void> init() async {
    _player ??= AudioPlayer();
  }

  void setSpeed(double v) {
    _speed = v;
    _player?.setSpeed(v);
  }

  Future<void> enqueueVoiceUrl(
    String url, {
    required String title,
    required String subtitle,
    String? iconUrl,
  }) async {
    _pending.add(
      PlayItem(
        title: title,
        subtitle: subtitle,
        isVoice: true,
        source: url,
        iconUrl: iconUrl,
      ),
    );
    _syncQueueLength();
    unawaited(_pump());
  }

  Future<void> enqueueWav(
    String path, {
    required String title,
    required String subtitle,
    String? iconUrl,
  }) async {
    debugPrint('[PLAY] enqueueWav q#${identityHashCode(this)} path=$path');
    _pending.add(
      PlayItem(
        title: title,
        subtitle: subtitle,
        isVoice: false,
        source: path,
        iconUrl: iconUrl,
      ),
    );
    _syncQueueLength();
    unawaited(_pump());
  }

  void clear() {
    _pending.clear();
    _syncQueueLength();
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    _pending.clear();
    _syncQueueLength();
    try {
      await _player?.stop();
    } catch (e) {
      logger.w('PlaybackQueue: stop failed: $e');
    }
    current.value = null;
  }

  Future<void> _pump() async {
    debugPrint('[PLAY] _pump enter q#${identityHashCode(this)} pumping=$_pumping');
    if (_pumping) return;
    _pumping = true;
    _idleTimer?.cancel();

    final player = _player ??= AudioPlayer();

    try {
      while (_pending.isNotEmpty) {
        final item = _pending.removeFirst();
        _syncQueueLength();
        _idleTimer?.cancel();
        current.value = item;

        final started = DateTime.now();
        debugPrint(
          '[PLAY] start ${item.isVoice ? "voice" : "tts"} "${item.title}" '
          'pendingLeft=${_pending.length} src=${item.source}',
        );
        try {
          await player.stop();
          if (item.isVoice) {
            await player.setUrl(item.source);
          } else {
            await player.setFilePath(item.source);
          }
          await player.setSpeed(_speed);
          await _playToEnd(player);
          debugPrint(
            '[PLAY] done "${item.title}" in '
            '${DateTime.now().difference(started).inMilliseconds}ms',
          );
        } catch (e) {
          debugPrint('[PLAY] FAILED "${item.title}" src=${item.source}: $e');
          logger.w('PlaybackQueue: failed to play ${item.source}: $e');
        } finally {
          try {
            await player.stop();
          } catch (_) {}
        }
      }
    } finally {
      _pumping = false;
      _scheduleIdleReset();
    }
  }

  void _scheduleIdleReset() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleResetDelay, () {
      if (!_pumping && _pending.isEmpty) {
        debugPrint('[PLAY] idle reset -> current=null');
        current.value = null;
      }
    });
  }

  Future<void> _playToEnd(AudioPlayer player) async {
    debugPrint('[PLAY] duration=${player.duration} state=${player.processingState}');
    await player.play();
  }

  void _syncQueueLength() => queueLength.value = _pending.length;
}

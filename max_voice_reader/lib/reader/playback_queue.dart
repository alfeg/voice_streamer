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

  const PlayItem({
    required this.title,
    required this.subtitle,
    required this.isVoice,
    required this.source,
  });
}

class PlaybackQueue {
  PlaybackQueue._();

  static final PlaybackQueue instance = PlaybackQueue._();

  AudioPlayer? _player;
  final Queue<PlayItem> _pending = Queue<PlayItem>();
  bool _pumping = false;
  double _speed = 1.0;

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
  }) async {
    _pending.add(
      PlayItem(title: title, subtitle: subtitle, isVoice: true, source: url),
    );
    _syncQueueLength();
    unawaited(_pump());
  }

  Future<void> enqueueWav(
    String path, {
    required String title,
    required String subtitle,
  }) async {
    _pending.add(
      PlayItem(title: title, subtitle: subtitle, isVoice: false, source: path),
    );
    _syncQueueLength();
    unawaited(_pump());
  }

  void clear() {
    _pending.clear();
    _syncQueueLength();
  }

  Future<void> stop() async {
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
    if (_pumping) return;
    _pumping = true;

    final player = _player ??= AudioPlayer();

    try {
      while (_pending.isNotEmpty) {
        final item = _pending.removeFirst();
        _syncQueueLength();
        current.value = item;

        try {
          if (item.isVoice) {
            await player.setUrl(item.source);
          } else {
            await player.setFilePath(item.source);
          }
          await player.setSpeed(_speed);
          await player.play();
          await _awaitCompletion(player);
        } catch (e) {
          logger.w('PlaybackQueue: failed to play ${item.source}: $e');
        }
      }
    } finally {
      current.value = null;
      _pumping = false;
    }
  }

  Future<void> _awaitCompletion(AudioPlayer player) async {
    final completer = Completer<void>();
    late final StreamSubscription<PlayerState> sub;
    sub = player.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    try {
      await completer.future;
    } finally {
      await sub.cancel();
    }
  }

  void _syncQueueLength() => queueLength.value = _pending.length;
}

import 'package:flutter/material.dart';

import '../reader/channel_config.dart';
import '../reader/playback_queue.dart';
import '../reader/reader_service.dart';
import '../tts/tts_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = ChannelConfig.speed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Плеер')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWatchButton(),
          const SizedBox(height: 16),
          _buildNowPlaying(),
          const SizedBox(height: 16),
          _buildQueueDepth(),
          const SizedBox(height: 24),
          _buildSpeedSlider(),
          const SizedBox(height: 16),
          _buildTtsStatus(),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => PlaybackQueue.instance.clear(),
            icon: const Icon(Icons.clear_all),
            label: const Text('Очистить очередь'),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: ReaderService.instance.watching,
      builder: (context, watching, _) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              if (watching) {
                ReaderService.instance.stopWatching();
              } else {
                ReaderService.instance.startWatching();
              }
            },
            icon: Icon(watching ? Icons.stop : Icons.play_arrow),
            label: Text(watching ? 'Остановить' : 'Начать'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNowPlaying() {
    return ValueListenableBuilder<PlayItem?>(
      valueListenable: PlaybackQueue.instance.current,
      builder: (context, item, _) {
        if (item == null) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.music_off),
              title: const Text('Ничего не воспроизводится'),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: Icon(
              item.isVoice ? Icons.mic : Icons.text_fields,
            ),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueDepth() {
    return ValueListenableBuilder<int>(
      valueListenable: PlaybackQueue.instance.queueLength,
      builder: (context, length, _) {
        return Text('В очереди: $length');
      },
    );
  }

  Widget _buildSpeedSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Скорость: ${_speed.toStringAsFixed(1)}×'),
        Slider(
          value: _speed,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          label: '${_speed.toStringAsFixed(1)}×',
          onChanged: (v) {
            setState(() => _speed = v);
            ChannelConfig.setSpeed(v);
            PlaybackQueue.instance.setSpeed(v);
          },
        ),
      ],
    );
  }

  Widget _buildTtsStatus() {
    if (TtsService.instance.isReady) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.warning_amber, color: cs.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Модель озвучки не установлена — текстовые каналы не читаются',
            style: TextStyle(color: cs.error),
          ),
        ),
      ],
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../backend/modules/chats.dart';
import '../core/storage/app_database.dart';
import '../core/storage/token_storage.dart';
import 'package:komet/frontend_reader/fullscreen_screen.dart';
import 'package:komet/reader/channel_config.dart';
import 'package:komet/reader/playback_queue.dart';
import 'package:komet/reader/reader_service.dart';
import 'package:komet/tts/tts_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _keepScreenOnKey = 'reader_keep_screen_on';

  late double _speed;
  Map<int, String> _titles = {};
  bool _keepScreenOn = false;

  @override
  void initState() {
    super.initState();
    _speed = ChannelConfig.speed;
    _loadTitles();
    _loadKeepScreenOn();
  }

  Future<void> _loadTitles() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    final rows = await AppDatabase.loadChats(accountId);
    final titles = <int, String>{};
    for (final row in rows) {
      final chat = CachedChat.fromDbRow(row);
      titles[chat.id] = chat.title ?? 'Канал ${chat.id}';
    }
    if (!mounted) return;
    setState(() => _titles = titles);
  }

  Future<void> _loadKeepScreenOn() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_keepScreenOnKey) ?? false;
    if (value) await WakelockPlus.enable();
    if (!mounted) return;
    setState(() => _keepScreenOn = value);
  }

  Future<void> _setKeepScreenOn(bool value) async {
    setState(() => _keepScreenOn = value);
    if (value) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenOnKey, value);
  }

  String _modeLabel(WatchMode mode) {
    switch (mode) {
      case WatchMode.voice:
        return 'Голос';
      case WatchMode.tts:
        return 'Текст→речь';
      case WatchMode.both:
        return 'Оба';
      case WatchMode.off:
        return 'Выкл';
    }
  }

  IconData _modeIcon(WatchMode mode) {
    switch (mode) {
      case WatchMode.voice:
        return Icons.mic;
      case WatchMode.tts:
        return Icons.text_fields;
      case WatchMode.both:
        return Icons.graphic_eq;
      case WatchMode.off:
        return Icons.volume_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Плеер')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWatchButton(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FullscreenScreen()),
              ),
              icon: const Icon(Icons.fullscreen),
              label: const Text('Полный экран'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildNowPlaying(),
          const SizedBox(height: 16),
          _buildQueueDepth(),
          const SizedBox(height: 16),
          _buildWatchedChannels(),
          const SizedBox(height: 8),
          _buildKeepScreenOn(),
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
            leading: _avatar(item),
            isThreeLine: true,
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              item.subtitle,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(item.isVoice ? Icons.mic : Icons.text_fields),
          ),
        );
      },
    );
  }

  Widget _buildWatchedChannels() {
    return ValueListenableBuilder<int>(
      valueListenable: ChannelConfig.revision,
      builder: (context, _, _) {
        final entries = ChannelConfig.all.entries
            .where((e) => e.value != WatchMode.off)
            .toList();
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Каналы на прослушке',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Нет активных каналов'),
                )
              else
                ...entries.map(
                  (e) => ListTile(
                    dense: true,
                    leading: Icon(_modeIcon(e.value)),
                    title: Text(
                      _titles[e.key] ?? 'Канал ${e.key}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(_modeLabel(e.value)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKeepScreenOn() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.screen_lock_portrait),
      title: const Text('Не выключать экран'),
      value: _keepScreenOn,
      onChanged: _setKeepScreenOn,
    );
  }

  Widget _avatar(PlayItem item) {
    final url = item.iconUrl;
    final letter = item.title.isNotEmpty ? item.title[0].toUpperCase() : '?';
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: CachedNetworkImageProvider(url),
      );
    }
    return CircleAvatar(child: Text(letter));
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

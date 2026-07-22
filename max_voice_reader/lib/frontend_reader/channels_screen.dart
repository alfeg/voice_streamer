import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../backend/modules/chats.dart';
import '../core/storage/app_database.dart';
import '../core/storage/token_storage.dart';
import '../reader/channel_config.dart';
import 'player_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  bool _loading = true;
  List<CachedChat> _channels = const [];

  @override
  void initState() {
    super.initState();
    ChannelConfig.revision.addListener(_onRevision);
    _load();
  }

  @override
  void dispose() {
    ChannelConfig.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) {
      if (!mounted) return;
      setState(() {
        _channels = const [];
        _loading = false;
      });
      return;
    }
    final rows = await AppDatabase.loadChats(accountId);
    final channels = rows
        .map(CachedChat.fromDbRow)
        .where((c) => c.type == 'CHANNEL')
        .toList();
    if (!mounted) return;
    setState(() {
      _channels = channels;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'Плеер',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_channels.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет каналов. Откройте канал в Max, затем вернитесь.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final channel = _channels[index];
        return _ChannelRow(channel: channel);
      },
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel});

  final CachedChat channel;

  @override
  Widget build(BuildContext context) {
    final title = channel.title ?? 'Без названия';
    final mode = ChannelConfig.modeFor(channel.id);
    return ListTile(
      leading: _buildAvatar(context, title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<WatchMode>(
        initialValue: mode,
        onSelected: (m) => ChannelConfig.setMode(channel.id, m),
        itemBuilder: (context) => const [
          PopupMenuItem(value: WatchMode.off, child: Text('Выкл')),
          PopupMenuItem(value: WatchMode.voice, child: Text('Голос')),
          PopupMenuItem(value: WatchMode.tts, child: Text('Текст→речь')),
          PopupMenuItem(value: WatchMode.both, child: Text('Оба')),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label(mode)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String title) {
    final iconUrl = channel.iconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: iconUrl,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => _letterAvatar(context, title),
          ),
        ),
      );
    }
    return _letterAvatar(context, title);
  }

  Widget _letterAvatar(BuildContext context, String title) {
    final letter = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        letter,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  String _label(WatchMode mode) {
    switch (mode) {
      case WatchMode.off:
        return 'Выкл';
      case WatchMode.voice:
        return 'Голос';
      case WatchMode.tts:
        return 'Текст→речь';
      case WatchMode.both:
        return 'Оба';
    }
  }
}

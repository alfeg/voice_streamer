import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:komet/reader/message_feed.dart';

class FullscreenScreen extends StatefulWidget {
  const FullscreenScreen({super.key});

  @override
  State<FullscreenScreen> createState() => _FullscreenScreenState();
}

class _FullscreenScreenState extends State<FullscreenScreen> {
  static const int _visible = 6;
  bool _prevWakelock = false;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  Future<void> _enter() async {
    _prevWakelock = await WakelockPlus.enabled;
    await WakelockPlus.enable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_prevWakelock) WakelockPlus.disable();
    super.dispose();
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<List<FeedItem>>(
                  valueListenable: MessageFeed.instance.items,
                  builder: (context, items, _) {
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'Ожидание сообщений…',
                          style: TextStyle(color: Colors.white38, fontSize: 22),
                        ),
                      );
                    }
                    final count = items.length < _visible
                        ? items.length
                        : _visible;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < count; i++) _row(items[i], i),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(FeedItem item, int depth) {
    final opacity = (1.0 - depth * 0.22).clamp(0.14, 1.0);
    final textSize = (36.0 - depth * 7.0).clamp(15.0, 36.0);
    final titleSize = (18.0 - depth * 2.0).clamp(11.0, 18.0);
    final url = item.iconUrl;

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (url != null && url.isNotEmpty)
                  CircleAvatar(
                    radius: titleSize * 0.8,
                    backgroundImage: CachedNetworkImageProvider(url),
                  )
                else
                  CircleAvatar(
                    radius: titleSize * 0.8,
                    backgroundColor: Colors.white12,
                    child: Text(
                      item.title.isNotEmpty ? item.title[0].toUpperCase() : '?',
                      style: TextStyle(color: Colors.white, fontSize: titleSize),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _time(item.time),
                  style: TextStyle(color: Colors.white38, fontSize: titleSize),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.text,
              style: TextStyle(
                color: Colors.white,
                fontSize: textSize,
                height: 1.15,
                fontStyle: item.isVoice ? FontStyle.italic : FontStyle.normal,
                fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

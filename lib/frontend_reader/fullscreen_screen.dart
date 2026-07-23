import 'dart:async';

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
  static const double _holdSeconds = 40;
  static const double _fadeSeconds = 60;
  static const double _floorOpacity = 0.4;

  bool _prevWakelock = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _enter();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _enter() async {
    _prevWakelock = await WakelockPlus.enabled;
    await WakelockPlus.enable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_prevWakelock) WakelockPlus.disable();
    super.dispose();
  }

  double _ageOpacity(DateTime time) {
    final age = DateTime.now().difference(time).inMilliseconds / 1000.0;
    if (age <= _holdSeconds) return 1.0;
    final t = (age - _holdSeconds) / _fadeSeconds;
    return (1.0 - t).clamp(_floorOpacity, 1.0);
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
                          for (var i = 0; i < count; i++)
                            TweenAnimationBuilder<double>(
                              key: ValueKey(items[i].id),
                              tween: Tween<double>(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOut,
                              builder: (context, t, child) => Transform.translate(
                                offset: Offset(0, (1 - t) * -24),
                                child: Opacity(opacity: t, child: child),
                              ),
                              child: _row(items[i], i),
                            ),
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
    final textSize = (36.0 - depth * 7.0).clamp(15.0, 36.0);
    final titleSize = (18.0 - depth * 2.0).clamp(11.0, 18.0);
    final url = item.iconUrl;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 800),
      opacity: _ageOpacity(item.time),
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

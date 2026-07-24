import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:komet/reader/message_feed.dart';

const int _visible = 6;
const double _holdSeconds = 40;
const double _fadeSeconds = 60;
const double _floorOpacity = 0.4;
const Duration _motionDuration = Duration(milliseconds: 550);

class FullscreenScreen extends StatefulWidget {
  const FullscreenScreen({super.key});

  @override
  State<FullscreenScreen> createState() => _FullscreenScreenState();
}

class _FullscreenScreenState extends State<FullscreenScreen> {
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
                    final count = items.length < _visible + 1
                        ? items.length
                        : _visible + 1;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < count; i++)
                            _FeedRow(
                              key: ValueKey(items[i].id),
                              item: items[i],
                              depth: i,
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
}

double _ageOpacity(DateTime time) {
  final age = DateTime.now().difference(time).inMilliseconds / 1000.0;
  if (age <= _holdSeconds) return 1.0;
  final t = (age - _holdSeconds) / _fadeSeconds;
  return (1.0 - t).clamp(_floorOpacity, 1.0);
}

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _FeedRow extends StatefulWidget {
  const _FeedRow({super.key, required this.item, required this.depth});

  final FeedItem item;
  final int depth;

  @override
  State<_FeedRow> createState() => _FeedRowState();
}

class _FeedRowState extends State<_FeedRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _grow;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _drop;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: _motionDuration);
    _grow = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    _fadeIn = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    _drop = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack));
    if (widget.depth == 0) {
      _entrance.forward();
    } else {
      _entrance.value = 1.0;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _grow,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _drop,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.depth.toDouble()),
            duration: _motionDuration,
            curve: Curves.easeOutCubic,
            builder: (context, depth, _) => _content(depth),
          ),
        ),
      ),
    );
  }

  Widget _content(double depth) {
    final item = widget.item;
    final double textSize = (36.0 - depth * 7.0).clamp(15.0, 36.0);
    final double titleSize = (18.0 - depth * 2.0).clamp(11.0, 18.0);
    final double slotFade = (_visible - depth).clamp(0.0, 1.0);
    final url = item.iconUrl;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 800),
      opacity: _ageOpacity(item.time) * slotFade,
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
                fontWeight: FontWeight.lerp(
                  FontWeight.w700,
                  FontWeight.w500,
                  depth.clamp(0.0, 1.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

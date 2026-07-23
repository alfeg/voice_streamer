import 'package:flutter/foundation.dart';

class FeedItem {
  final String id;
  final String title;
  final String? iconUrl;
  final String text;
  final bool isVoice;
  final DateTime time;

  const FeedItem({
    required this.id,
    required this.title,
    required this.iconUrl,
    required this.text,
    required this.isVoice,
    required this.time,
  });
}

class MessageFeed {
  MessageFeed._();

  static final MessageFeed instance = MessageFeed._();

  static const int _max = 12;

  final ValueNotifier<List<FeedItem>> items =
      ValueNotifier<List<FeedItem>>(const []);

  void add(FeedItem item) {
    final next = <FeedItem>[item, ...items.value];
    if (next.length > _max) next.removeRange(_max, next.length);
    items.value = next;
  }

  void clear() => items.value = const [];
}

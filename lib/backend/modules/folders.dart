import 'dart:convert';

import '../models/chat_folder.dart';
import '../../core/storage/app_database.dart';

class FoldersModule {
  static const _syncKey = 'chat_folders_snapshot';
  static const _listReadyKey = 'chat_folders_list_ready';

  static Future<void> markFoldersListReady(int accountId) async {
    await AppDatabase.setSyncValue(accountId, _listReadyKey, '1');
  }

  static void sortFoldersInPlace(
    List<ChatFolder> folders,
    List<dynamic>? foldersOrder,
  ) {
    if (foldersOrder == null || foldersOrder.isEmpty) return;
    final orderIndex = <String, int>{};
    for (var i = 0; i < foldersOrder.length; i++) {
      orderIndex.putIfAbsent(foldersOrder[i].toString(), () => i);
    }
    folders.sort((a, b) {
      final aIndex = orderIndex[a.id] ?? -1;
      final bIndex = orderIndex[b.id] ?? -1;
      if (aIndex == -1 && bIndex == -1) return 0;
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
  }

  static List<ChatFolder> _parseFolderList(
    List<dynamic> json, {
    bool lenient = true,
  }) {
    if (lenient) {
      return json
          .map((e) {
            try {
              final m = e is Map<String, dynamic>
                  ? e
                  : Map<String, dynamic>.from(e as Map);
              return ChatFolder.fromJson(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<ChatFolder>()
          .toList();
    }
    return json.map((e) {
      final m = e is Map<String, dynamic>
          ? e
          : Map<String, dynamic>.from(e as Map);
      return ChatFolder.fromJson(m);
    }).toList();
  }

  static Future<void> _persist(
    int accountId,
    List<ChatFolder> folders,
    List<dynamic>? order,
  ) async {
    await AppDatabase.setSyncValue(
      accountId,
      _syncKey,
      jsonEncode({
        'folders': folders.map((f) => f.toJson()).toList(),
        'foldersOrder': order,
      }),
    );
  }

  static Future<void> applyFromLoginConfig(
    int accountId,
    Map<dynamic, dynamic> config,
  ) async {
    final chatFolders = config['chatFolders'];
    if (chatFolders is! Map) return;
    final foldersJson = chatFolders['FOLDERS'] as List<dynamic>?;
    if (foldersJson == null) return;
    final order = chatFolders['foldersOrder'] as List<dynamic>?;
    final folders = _parseFolderList(foldersJson);
    sortFoldersInPlace(folders, order);
    await _persist(accountId, folders, order);
    await markFoldersListReady(accountId);
  }
}

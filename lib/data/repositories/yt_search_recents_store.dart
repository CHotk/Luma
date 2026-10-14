import 'dart:convert';

import '../storage/key_value_store.dart';

/// 頻道頁搜尋的「最近搜尋」（2026-10-14，設計稿第 1 版）。所有頻道共用
/// 一份，最新的在前面，最多留 [max] 筆；只存本機（是搜尋紀錄，不是設定）。
class YtSearchRecentsStore {
  YtSearchRecentsStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.search_recents.v1';
  static const max = 8;

  Future<List<String>> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return [for (final q in decoded) '$q'];
    } on FormatException {
      // 壞掉的當沒有。
    }
    return const [];
  }

  Future<List<String>> add(String query) async {
    final q = query.trim();
    final next = [
      if (q.isNotEmpty) q,
      for (final r in await load())
        if (r != q) r,
    ].take(max).toList();
    await _store.write(_key, jsonEncode(next));
    return next;
  }

  Future<List<String>> remove(String query) async {
    final next = [
      for (final r in await load())
        if (r != query) r,
    ];
    await _store.write(_key, jsonEncode(next));
    return next;
  }
}

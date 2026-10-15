import 'dart:convert';

import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 頻道頁搜尋的「最近搜尋」（2026-10-14，設計稿第 1 版）。所有頻道共用
/// 一份，最新的在前面，最多留 [max] 筆。2026-10-15 使用者要求跨裝置同步：
/// 整份清單一筆，後改的贏（刪掉的也跟著同步）。
class YtSearchRecentsStore {
  YtSearchRecentsStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.search_recents.v1';
  static const max = 8;

  /// 雲端上的檔名。
  static const cloudKey = 'yt_search_recents.json';

  /// 跨裝置同步（2026-10-15 使用者要求），見 [StampedSettingStore]。
  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<List<String>> load() async {
    final raw = await record.loadValue();
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
    await record.saveValue(jsonEncode(next));
    return next;
  }

  Future<List<String>> remove(String query) async {
    final next = [
      for (final r in await load())
        if (r != query) r,
    ];
    await record.saveValue(jsonEncode(next));
    return next;
  }
}

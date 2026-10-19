import 'dart:convert';

import '../storage/key_value_store.dart';

/// 音樂的播放紀錄（2026-10-19 使用者要求「跟 YT 差不多記錄下」）：版本
/// （影片）id → 每一次開始播的時間。一筆都不刪（log 類資料的規則），畫面
/// 要少看幾筆是顯示上的事。跟 YT 管理的看過紀錄分開記（音樂自己一份）。
///
/// 跨裝置同步是聯集：兩邊的時間合在一起去掉重複，紀錄只會變多。
class MusicPlayLogStore {
  MusicPlayLogStore(this._store);

  final KeyValueStore _store;

  static const _key = 'music.play_log.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'music_play_log.json';

  Future<Map<String, List<DateTime>>> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    try {
      return decode(raw);
    } on FormatException {
      return {};
    }
  }

  Future<void> save(Map<String, List<DateTime>> log) =>
      _store.write(_key, encode(log));

  static String encode(Map<String, List<DateTime>> log) => jsonEncode({
    for (final e in log.entries)
      e.key: [for (final t in e.value) t.toIso8601String()],
  });

  static Map<String, List<DateTime>> decode(String raw) => {
    for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
      e.key: [
        for (final t in (e.value as List)) ?DateTime.tryParse(t as String),
      ],
  };

  /// 聯集：同一部影片兩邊的時間合起來、去掉重複、舊到新排好。
  static Map<String, List<DateTime>> merge(
    Map<String, List<DateTime>> a,
    Map<String, List<DateTime>> b,
  ) {
    final out = <String, List<DateTime>>{};
    for (final id in {...a.keys, ...b.keys}) {
      final all = {
        for (final t in [...?a[id], ...?b[id]]) t.toUtc().toIso8601String(): t,
      }.values.toList()..sort();
      out[id] = all;
    }
    return out;
  }

  /// 總筆數（同步回報用）。
  static int count(Map<String, List<DateTime>> log) =>
      log.values.fold(0, (s, l) => s + l.length);
}

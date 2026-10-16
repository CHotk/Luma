import 'dart:convert';

import '../storage/key_value_store.dart';

/// 音樂分類的頻道裡，使用者標成「歌曲」的影片（2026-10-16 使用者要求）。
///
/// 記在影片上，不是記在分類上：頻道換到別的分類，「歌曲」按鈕跟 ♪ 只是
/// 不顯示，資料照樣留著，換回音樂分類就全部回來。
///
/// 每一部記「是不是歌曲＋改的時間」：取消標記也要能同步到別台（只記集合
/// 的話，取消了別台又會把它加回來），同步時同一部比時間、後改的贏。
class YtVideoSongStore {
  YtVideoSongStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.video_song.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'yt_video_songs.json';

  /// 影片 id → (是不是歌曲, 改的時間)。
  Future<Map<String, ({bool song, DateTime at})>> loadRecords() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    return decode(raw);
  }

  /// 現在標成歌曲的影片 id。
  Future<Set<String>> loadIds() async => {
    for (final e in (await loadRecords()).entries)
      if (e.value.song) e.key,
  };

  Future<void> set(String videoId, bool song) async {
    final all = await loadRecords();
    all[videoId] = (song: song, at: DateTime.now());
    await saveRecords(all);
  }

  Future<void> saveRecords(Map<String, ({bool song, DateTime at})> all) =>
      _store.write(_key, encode(all));

  static String encode(Map<String, ({bool song, DateTime at})> all) =>
      jsonEncode({
        for (final e in all.entries)
          e.key: {'song': e.value.song, 'at': e.value.at.toIso8601String()},
      });

  static Map<String, ({bool song, DateTime at})> decode(String raw) => {
    for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
      e.key: (
        song: (e.value as Map)['song'] as bool? ?? false,
        at:
            DateTime.tryParse((e.value as Map)['at'] as String? ?? '') ??
            DateTime(2000),
      ),
  };

  /// 兩邊合併：同一部比改的時間，後改的贏。
  static Map<String, ({bool song, DateTime at})> merge(
    Map<String, ({bool song, DateTime at})> a,
    Map<String, ({bool song, DateTime at})> b,
  ) {
    final out = {...a};
    for (final e in b.entries) {
      final mine = out[e.key];
      if (mine == null || e.value.at.isAfter(mine.at)) out[e.key] = e.value;
    }
    return out;
  }
}

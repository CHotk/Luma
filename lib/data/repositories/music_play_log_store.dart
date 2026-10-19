import 'dart:convert';

import '../storage/key_value_store.dart';

/// 一次播放（2026-10-19）：什麼時候、從哪裡點的、用 YouTube 還是 App 內播放。
class MusicPlay {
  const MusicPlay({required this.at, this.from = '', this.mode = ''});

  final DateTime at;

  /// 從哪裡點的（「首頁・快速選曲」「歌手頁・隨機」「自動接下一首」…）。
  final String from;

  /// 'youtube'（轉到 YouTube）或 'app'（App 內播放）；舊紀錄沒有。
  final String mode;

  String get modeLabel => switch (mode) {
    'youtube' => 'YouTube',
    'app' => 'App 內播放',
    _ => '',
  };

  /// 合併時判斷是不是同一筆。
  String get key => '${at.toUtc().toIso8601String()}|$from|$mode';

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    if (from.isNotEmpty) 'from': from,
    if (mode.isNotEmpty) 'mode': mode,
  };

  static MusicPlay? fromJson(Object? j) {
    // 2026-10-19 最早幾筆只存時間字串。
    if (j is String) {
      final t = DateTime.tryParse(j);
      return t == null ? null : MusicPlay(at: t);
    }
    if (j is! Map) return null;
    final t = DateTime.tryParse(j['at'] as String? ?? '');
    if (t == null) return null;
    return MusicPlay(
      at: t,
      from: j['from'] as String? ?? '',
      mode: j['mode'] as String? ?? '',
    );
  }
}

/// 音樂的播放紀錄（2026-10-19 使用者要求「跟 YT 差不多記錄下」）：版本
/// （影片）id → 每一次播放。一筆都不刪（log 類資料的規則），畫面要少看
/// 幾筆是顯示上的事。跟 YT 管理的看過紀錄分開記（音樂自己一份）。
///
/// 跨裝置同步是聯集：兩邊合在一起去掉重複，紀錄只會變多。
class MusicPlayLogStore {
  MusicPlayLogStore(this._store);

  final KeyValueStore _store;

  static const _key = 'music.play_log.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'music_play_log.json';

  Future<Map<String, List<MusicPlay>>> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    try {
      return decode(raw);
    } on FormatException {
      return {};
    }
  }

  Future<void> save(Map<String, List<MusicPlay>> log) =>
      _store.write(_key, encode(log));

  static String encode(Map<String, List<MusicPlay>> log) => jsonEncode({
    for (final e in log.entries) e.key: [for (final p in e.value) p.toJson()],
  });

  static Map<String, List<MusicPlay>> decode(String raw) => {
    for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
      e.key: [for (final p in (e.value as List)) ?MusicPlay.fromJson(p)],
  };

  /// 聯集：同一部影片兩邊的紀錄合起來、去掉重複、舊到新排好。
  static Map<String, List<MusicPlay>> merge(
    Map<String, List<MusicPlay>> a,
    Map<String, List<MusicPlay>> b,
  ) {
    final out = <String, List<MusicPlay>>{};
    for (final id in {...a.keys, ...b.keys}) {
      final all = {
        for (final p in [...?a[id], ...?b[id]]) p.key: p,
      }.values.toList()..sort((x, y) => x.at.compareTo(y.at));
      out[id] = all;
    }
    return out;
  }

  /// 總筆數（同步回報用）。
  static int count(Map<String, List<MusicPlay>> log) =>
      log.values.fold(0, (s, l) => s + l.length);
}

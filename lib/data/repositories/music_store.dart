import 'dart:convert';

import '../../domain/models/music.dart';
import '../storage/key_value_store.dart';

/// 音樂功能的資料存檔（2026-10-19）：整份 [MusicData] 存成一筆 JSON，含刪掉
/// 的墓碑；跨裝置同步一筆一筆比改的時間（見 `R2SyncService.syncMusic`）。
class MusicStore {
  MusicStore(this._store);

  final KeyValueStore _store;

  static const _key = 'music.data.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'music.json';

  Future<MusicData> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return MusicData.empty;
    try {
      return MusicData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return MusicData.empty;
    }
  }

  Future<void> save(MusicData data) =>
      _store.write(_key, jsonEncode(data.toJson()));
}

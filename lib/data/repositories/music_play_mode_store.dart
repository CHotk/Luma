import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 音樂點歌要怎麼播（2026-10-19 使用者要求：跟 YT 一樣可以選內嵌或轉到
/// YouTube，**預設轉到 YouTube**）。音樂自己一份設定，不跟 YT 的共用。
enum MusicPlayMode {
  /// 開 YouTube（新分頁或 YouTube App）。好幾首一起播時用 YouTube 的臨時
  /// 播放清單帶過去。
  youtube,

  /// App 裡的播放器（迷你列＋全螢幕，播完自動下一首）。
  embedded;

  static MusicPlayMode fromName(String? n) =>
      n == 'embedded' ? MusicPlayMode.embedded : MusicPlayMode.youtube;
}

class MusicPlayModeStore {
  MusicPlayModeStore(this._store);

  final KeyValueStore _store;

  static const _key = 'music.play_mode.v1';
  static const defaultMode = MusicPlayMode.youtube;

  /// 雲端上的檔名。
  static const cloudKey = 'music_play_mode.json';

  /// 跨裝置同步，見 [StampedSettingStore]。
  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<MusicPlayMode> load() async =>
      MusicPlayMode.fromName(await record.loadValue());

  Future<void> save(MusicPlayMode mode) => record.saveValue(mode.name);
}

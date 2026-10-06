import '../storage/key_value_store.dart';

/// 點影片要怎麼開：內嵌播放（App 裡彈出播放器，不用離開）還是開新分頁去
/// 真正的 YouTube（2026-09-30 使用者要求：開新分頁那一刻感覺像離開了
/// App，希望能有內嵌播放器可以選；使用者原話「讓我有設定內可以調 預設
/// 內嵌」——預設用內嵌，設定頁能切回開新分頁）。
enum YtVideoOpenMode {
  embedded,
  external;

  static YtVideoOpenMode fromName(String? name) => switch (name) {
    'external' => YtVideoOpenMode.external,
    _ => YtVideoOpenMode.embedded,
  };
}

class YtVideoOpenModeStore {
  YtVideoOpenModeStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.video_open_mode.v1';
  // 預設開新分頁（2026-10-06 使用者要求：點影片預設開新分頁，不是內嵌
  // 播放；設定頁「點影片時」照樣能切回內嵌）。只影響沒在設定頁選過的
  // 裝置，選過的照舊。
  static const defaultMode = YtVideoOpenMode.external;

  Future<YtVideoOpenMode> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultMode;
    return YtVideoOpenMode.fromName(raw);
  }

  Future<void> save(YtVideoOpenMode mode) => _store.write(_key, mode.name);
}

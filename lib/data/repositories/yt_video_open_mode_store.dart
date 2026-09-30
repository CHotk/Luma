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
  static const defaultMode = YtVideoOpenMode.embedded;

  Future<YtVideoOpenMode> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultMode;
    return YtVideoOpenMode.fromName(raw);
  }

  Future<void> save(YtVideoOpenMode mode) => _store.write(_key, mode.name);
}

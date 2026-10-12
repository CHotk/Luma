import '../storage/key_value_store.dart';

/// YT「依影片顯示」要不要連冷藏頻道一起抓（2026-10-12 使用者要求：預設
/// 不抓冷藏頻道，設定裡可以打開）。只存本機，跟「點影片時」一樣。
class YtVideoIncludeColdStore {
  YtVideoIncludeColdStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.video_include_cold.v1';
  static const defaultInclude = false;

  Future<bool> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultInclude;
    return raw == 'true';
  }

  Future<void> save(bool include) => _store.write(_key, '$include');
}

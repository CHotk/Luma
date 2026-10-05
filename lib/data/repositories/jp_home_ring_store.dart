import '../storage/key_value_store.dart';

/// 日文首頁要不要顯示「今天進度」那一圈（2026-10-05 使用者要求：預設
/// 隱藏，想看再到設定打開）。
class JpHomeRingStore {
  JpHomeRingStore(this._store);

  final KeyValueStore _store;

  static const _key = 'jp_home.show_progress_ring.v1';
  static const defaultShow = false;

  Future<bool> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultShow;
    return raw == 'true';
  }

  Future<void> save(bool show) => _store.write(_key, '$show');
}

import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 日文首頁要不要顯示「今天進度」那一圈（2026-10-05 使用者要求：預設
/// 隱藏，想看再到設定打開）。
class JpHomeRingStore {
  JpHomeRingStore(this._store);

  final KeyValueStore _store;

  static const _key = 'jp_home.show_progress_ring.v1';
  static const defaultShow = false;

  /// 雲端上的檔名。
  static const cloudKey = 'jp_home_ring.json';

  /// 跨裝置同步（2026-10-15 使用者要求），見 [StampedSettingStore]。
  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<bool> load() async {
    final raw = await record.loadValue();
    if (raw == null) return defaultShow;
    return raw == 'true';
  }

  Future<void> save(bool show) => record.saveValue('$show');
}

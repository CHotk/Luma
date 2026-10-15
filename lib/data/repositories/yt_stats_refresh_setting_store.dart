import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// YT 頻道訂閱人數多久重新問一次 API，使用者自己在設定頁調
/// （2026-09-29 使用者要求：原本寫死 12 小時，改成可設定天數，預設
/// 一天一輪）。2026-10-15 使用者要求也要跨裝置同步。
class YtStatsRefreshSettingStore {
  YtStatsRefreshSettingStore(this._store);

  static const _key = 'yt_tracker.stats_refresh_days.v1';

  /// 沒設定過就是一週一輪（2026-09-29 使用者把原本的「一天」改成
  /// 「一週」，訂閱人數本來就不會天天大變，沒必要這麼常問 API）。
  static const defaultDays = 7;

  /// 雲端上的檔名。
  static const cloudKey = 'yt_stats_refresh_days.json';

  final KeyValueStore _store;

  /// 跨裝置同步（2026-10-15 使用者要求），見 [StampedSettingStore]。
  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<int> load() async {
    final raw = await record.loadValue();
    if (raw == null) return defaultDays;
    return int.tryParse(raw) ?? defaultDays;
  }

  Future<void> save(int days) => record.saveValue('$days');
}

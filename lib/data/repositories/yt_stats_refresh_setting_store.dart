import '../storage/key_value_store.dart';

/// YT 頻道訂閱人數多久重新問一次 API，使用者自己在設定頁調
/// （2026-09-29 使用者要求：原本寫死 12 小時，改成可設定天數，預設
/// 一天一輪）。存本機、跨裝置不用同步（單純省配額的節流設定，不是
/// 使用者的資料）。
class YtStatsRefreshSettingStore {
  YtStatsRefreshSettingStore(this._store);

  static const _key = 'yt_tracker.stats_refresh_days.v1';

  /// 沒設定過就是一天一輪。
  static const defaultDays = 1;

  final KeyValueStore _store;

  Future<int> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return defaultDays;
    return int.tryParse(raw) ?? defaultDays;
  }

  Future<void> save(int days) => _store.write(_key, '$days');
}

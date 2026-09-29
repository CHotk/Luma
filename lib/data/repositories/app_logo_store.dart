import '../storage/key_value_store.dart';

/// 使用者在設定頁選的 App Logo（2026-09-29 使用者要求）：存的是
/// `assets/images/app_logo/` 底下某張圖的完整資產路徑，null／讀不到就是
/// 沒選過，退回預設的 `logo.png`。純外觀設定，不用跨裝置同步。
class AppLogoStore {
  AppLogoStore(this._store);

  static const _key = 'app.logo_asset_path.v1';

  final KeyValueStore _store;

  Future<String?> load() => _store.read(_key);

  Future<void> save(String assetPath) => _store.write(_key, assetPath);

  Future<void> clear() => _store.remove(_key);
}

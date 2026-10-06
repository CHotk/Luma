import '../storage/key_value_store.dart';

/// App 首頁（`/start`）用哪種樣子（2026-10-05 使用者要求：多做一種
/// `design-history/已選擇完成/首頁設計/02_今日儀表板`，設定裡可以切換）。
/// 預設是原本的圖示格（2026-10-06 使用者要求改回預設圖示格）。
enum AppHomeStyle {
  /// 今日儀表板：打開就看到各功能今天的狀態，點卡片進去。
  dashboard,

  /// 原本的圖示格啟動器（設計稿 01）。預設。
  grid;

  static AppHomeStyle fromName(String? name) =>
      name == 'dashboard' ? AppHomeStyle.dashboard : AppHomeStyle.grid;
}

class AppHomeStyleStore {
  AppHomeStyleStore(this._store);

  final KeyValueStore _store;

  static const _key = 'app_home.style.v1';
  static const defaultStyle = AppHomeStyle.grid;

  Future<AppHomeStyle> load() async =>
      AppHomeStyle.fromName(await _store.read(_key));

  Future<void> save(AppHomeStyle style) => _store.write(_key, style.name);
}

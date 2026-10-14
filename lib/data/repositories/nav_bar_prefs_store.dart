import 'dart:convert';

import '../storage/key_value_store.dart';

/// 底部浮動分頁列要顯示哪一種（2026-10-14 使用者要求）。
enum NavBarMode {
  /// 全 App 共用一條：英文／日文／YT。
  global('全 App 共用'),

  /// 各功能自己的（例如 YT 的頻道／影片／播放清單）；那個功能沒有就不顯示。
  feature('各功能自己的'),

  /// 都不要。
  off('不顯示');

  const NavBarMode(this.label);
  final String label;
}

/// 底部分頁列的設定，跨裝置同步（2026-10-14 使用者要求）。整組存成一筆
/// 「設定＋改的時間」，同步時比時間，後改的贏（見
/// `R2SyncService.syncNavBarPrefs`），跟 YT 顯示設定同一套。
class NavBarPrefs {
  const NavBarPrefs({this.mode = NavBarMode.global, required this.updatedAt});

  final NavBarMode mode;
  final DateTime updatedAt;

  /// 沒設定過：預設全 App 共用，時間給很舊，雲端有設定就用雲端的。
  static final defaults = NavBarPrefs(updatedAt: DateTime(2000));

  NavBarPrefs copyWith({NavBarMode? mode, DateTime? updatedAt}) => NavBarPrefs(
    mode: mode ?? this.mode,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NavBarPrefs.fromJson(Map<String, dynamic> j) => NavBarPrefs(
    mode: NavBarMode.values.firstWhere(
      (m) => m.name == j['mode'],
      orElse: () => NavBarMode.global,
    ),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime(2000),
  );
}

class NavBarPrefsStore {
  NavBarPrefsStore(this._store);

  final KeyValueStore _store;

  static const _key = 'app.nav_bar_prefs.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'nav_bar_prefs.json';

  /// 沒設定過是 null（同步時就不上傳，用雲端的或預設值）。
  Future<NavBarPrefs?> loadRecord() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return NavBarPrefs.fromJson(decoded);
    } on FormatException {
      // 壞掉的當沒設定過。
    }
    return null;
  }

  Future<NavBarPrefs> load() async =>
      await loadRecord() ?? NavBarPrefs.defaults;

  /// 使用者改設定：蓋上現在時間再存。
  Future<NavBarPrefs> save(NavBarPrefs prefs) async {
    final stamped = prefs.copyWith(updatedAt: DateTime.now());
    await saveRecord(stamped);
    return stamped;
  }

  /// 原樣存（同步從雲端帶回來的，時間不能改）。
  Future<void> saveRecord(NavBarPrefs prefs) =>
      _store.write(_key, jsonEncode(prefs.toJson()));
}

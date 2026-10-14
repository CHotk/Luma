import 'dart:convert';

import '../storage/key_value_store.dart';

/// YT 管理的顯示設定，跨裝置同步（2026-10-12 使用者要求：這類設定都要
/// 能多裝置同步）。整組存成一筆「設定＋改的時間」，同步時比時間，後改
/// 的贏（見 `R2SyncService.syncYtDisplayPrefs`），跟 USDT 匯率同一套。
class YtDisplayPrefs {
  const YtDisplayPrefs({
    this.videoIncludeCold = false,
    this.videoIncludePending = false,
    this.searchUseApi = true,
    this.searchShowAll = true,
    this.showScrollbar = true,
    this.showBackToTop = true,
    this.removedCheckDays = defaultRemovedCheckDays,
    this.backToTopRight = defaultBackToTopRight,
    this.backToTopBottom = defaultBackToTopBottom,
    required this.updatedAt,
  });

  /// 「依影片顯示」要不要連冷藏頻道一起抓（2026-10-12：預設不抓）。
  final bool videoIncludeCold;

  /// 「依影片顯示」要不要連待評鑑（還沒分區）的頻道一起抓（2026-10-14
  /// 使用者要求：跟冷藏一樣預設不抓，設定可以改）。
  final bool videoIncludePending;

  /// 頻道頁搜尋：true＝快取找完再向 YouTube 把整個頻道抓完（預設），
  /// false＝只搜快取、不打 API（2026-10-12 使用者定的規則）。
  final bool searchUseApi;

  /// 搜尋結果照樣列出已看過、已隱藏的（加標示），不受「隱藏已看過／
  /// 顯示已隱藏」影響（預設）；false＝照那兩個開關篩。
  final bool searchShowAll;

  /// 頻道詳情頁右側一直顯示捲動條（2026-10-12：預設開）。
  final bool showScrollbar;

  /// 頻道詳情頁滑下去後右下角的「回到最上面」（2026-10-12：預設開）。
  final bool showBackToTop;

  /// 影片下架檢查多久一次，天數；0＝不檢查（2026-10-12 使用者要求：設定
  /// 能調、跨裝置同步）。見 `YtRemovedVideoChecker`。
  final int removedCheckDays;

  static const defaultRemovedCheckDays = 14;

  /// 「回到最上面」按鈕離右邊、下面多遠（2026-10-12 使用者要求：起始
  /// 位置靠上一點、可以拖；拖完記住，跟著同步）。
  final double backToTopRight;
  final double backToTopBottom;

  static const defaultBackToTopRight = 10.0;
  static const defaultBackToTopBottom = 110.0;

  /// 設定頁給的選項（天）：一週、兩週、一個月、不檢查。
  static const removedCheckChoices = [7, 14, 30, 0];

  final DateTime updatedAt;

  /// 沒設定過：全部預設值，時間給很舊，雲端有設定就用雲端的。
  static final defaults = YtDisplayPrefs(updatedAt: DateTime(2000));

  YtDisplayPrefs copyWith({
    bool? videoIncludeCold,
    bool? videoIncludePending,
    bool? searchUseApi,
    bool? searchShowAll,
    bool? showScrollbar,
    bool? showBackToTop,
    int? removedCheckDays,
    double? backToTopRight,
    double? backToTopBottom,
    DateTime? updatedAt,
  }) => YtDisplayPrefs(
    videoIncludeCold: videoIncludeCold ?? this.videoIncludeCold,
    videoIncludePending: videoIncludePending ?? this.videoIncludePending,
    searchUseApi: searchUseApi ?? this.searchUseApi,
    searchShowAll: searchShowAll ?? this.searchShowAll,
    showScrollbar: showScrollbar ?? this.showScrollbar,
    showBackToTop: showBackToTop ?? this.showBackToTop,
    removedCheckDays: removedCheckDays ?? this.removedCheckDays,
    backToTopRight: backToTopRight ?? this.backToTopRight,
    backToTopBottom: backToTopBottom ?? this.backToTopBottom,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'videoIncludeCold': videoIncludeCold,
    'videoIncludePending': videoIncludePending,
    'searchUseApi': searchUseApi,
    'searchShowAll': searchShowAll,
    'showScrollbar': showScrollbar,
    'showBackToTop': showBackToTop,
    'removedCheckDays': removedCheckDays,
    'backToTopRight': backToTopRight,
    'backToTopBottom': backToTopBottom,
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 欄位缺的用預設值（之後加新設定，舊裝置上傳的檔案也讀得進來）。
  factory YtDisplayPrefs.fromJson(Map<String, dynamic> j) => YtDisplayPrefs(
    videoIncludeCold: j['videoIncludeCold'] as bool? ?? false,
    videoIncludePending: j['videoIncludePending'] as bool? ?? false,
    searchUseApi: j['searchUseApi'] as bool? ?? true,
    searchShowAll: j['searchShowAll'] as bool? ?? true,
    showScrollbar: j['showScrollbar'] as bool? ?? true,
    showBackToTop: j['showBackToTop'] as bool? ?? true,
    removedCheckDays:
        (j['removedCheckDays'] as num?)?.toInt() ?? defaultRemovedCheckDays,
    backToTopRight:
        (j['backToTopRight'] as num?)?.toDouble() ?? defaultBackToTopRight,
    backToTopBottom:
        (j['backToTopBottom'] as num?)?.toDouble() ?? defaultBackToTopBottom,
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime(2000),
  );
}

class YtDisplayPrefsStore {
  YtDisplayPrefsStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.display_prefs.v1';

  /// 2026-10-12 早上「依影片顯示也抓冷藏」先做成只存本機的開關，同一天
  /// 改成整組同步；舊開關有存過就帶進來。
  static const _legacyIncludeColdKey = 'yt_tracker.video_include_cold.v1';

  /// 雲端上的檔名。
  static const cloudKey = 'yt_display_prefs.json';

  /// 沒設定過是 null（同步時就不上傳，用雲端的或預設值）。
  Future<YtDisplayPrefs?> loadRecord() async {
    final raw = await _store.read(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return YtDisplayPrefs.fromJson(decoded);
        }
      } on FormatException {
        // 壞掉的當沒設定過。
      }
    }
    final legacy = await _store.read(_legacyIncludeColdKey);
    if (legacy == 'true') {
      return YtDisplayPrefs.defaults.copyWith(videoIncludeCold: true);
    }
    return null;
  }

  Future<YtDisplayPrefs> load() async =>
      await loadRecord() ?? YtDisplayPrefs.defaults;

  /// 使用者在設定頁改的：蓋上現在的時間。
  Future<YtDisplayPrefs> save(YtDisplayPrefs prefs) async {
    final stamped = prefs.copyWith(updatedAt: DateTime.now());
    await saveRecord(stamped);
    return stamped;
  }

  /// 同步帶回來的：原樣存，不改時間。
  Future<void> saveRecord(YtDisplayPrefs prefs) =>
      _store.write(_key, jsonEncode(prefs.toJson()));
}

import 'dart:convert';

import '../storage/key_value_store.dart';

/// 一個值＋改的時間（同步時比時間，後改的贏）。
class StampedSetting {
  const StampedSetting(this.value, this.updatedAt);

  /// 存成字串（enum 名稱、數字、true/false、JSON 都可以）。
  final String value;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'value': value,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static StampedSetting? fromJson(Object? j) {
    if (j is! Map<String, dynamic> || j['value'] is! String) return null;
    return StampedSetting(
      j['value'] as String,
      DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime(2000),
    );
  }
}

/// 只有一個值的設定，跨裝置同步用（2026-10-15 使用者要求：原本只存本機的
/// 點影片時、播放器樣式、訂閱人數更新頻率、日文進度圈、首頁樣式、最近搜尋
/// 都要同步）。本機存成 `{value, updatedAt}`，同步見
/// `R2SyncService.syncStampedSetting`，跟 [YtDisplayPrefsStore] 同一套規則。
///
/// 舊版直接存值（不是 JSON）：讀得進來，時間當很舊，雲端有就用雲端的。
class StampedSettingStore {
  StampedSettingStore(this._store, {required this.key, required this.cloudKey});

  final KeyValueStore _store;

  /// 本機的 key（沿用舊的，舊值才讀得到）。
  final String key;

  /// 雲端上的檔名。
  final String cloudKey;

  /// 沒設定過是 null（同步時就不上傳，用雲端的或預設值）。
  Future<StampedSetting?> loadRecord() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    if (raw.startsWith('{')) {
      try {
        final r = StampedSetting.fromJson(jsonDecode(raw));
        if (r != null) return r;
      } on FormatException {
        // 不是我們的格式，當舊版的值。
      }
    }
    return StampedSetting(raw, DateTime(2000));
  }

  Future<String?> loadValue() async => (await loadRecord())?.value;

  /// 使用者改的：蓋上現在的時間。
  Future<void> saveValue(String value) =>
      saveRecord(StampedSetting(value, DateTime.now()));

  /// 同步帶回來的：原樣存，不改時間。
  Future<void> saveRecord(StampedSetting record) =>
      _store.write(key, jsonEncode(record.toJson()));
}

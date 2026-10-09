import 'dart:convert';

import '../storage/key_value_store.dart';

/// 交易&自律裡 USDT 換台幣用的匯率（2026-10-10 使用者要求：USDT 後面加上
/// 台幣換算，預設 31，設定可改；接著要求跨裝置同步）。存成「匯率＋改的
/// 時間」，同步時比時間，後改的贏（見 `R2SyncService.syncUsdtTwdRate`）。
class UsdtTwdRateRecord {
  const UsdtTwdRateRecord({required this.rate, required this.updatedAt});

  final double rate;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'rate': rate,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory UsdtTwdRateRecord.fromJson(Map<String, dynamic> json) =>
      UsdtTwdRateRecord(
        rate: (json['rate'] as num).toDouble(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class UsdtTwdRateStore {
  UsdtTwdRateStore(this._store);

  static const _key = 'trade_log.usdt_twd_rate.v1';

  /// 雲端上的檔名，一個設定一個檔。
  static const cloudKey = 'usdt_twd_rate.json';

  static const defaultRate = 31.0;

  final KeyValueStore _store;

  /// 沒設定過是 null（同步時就不上傳，用雲端的或預設值）。
  Future<UsdtTwdRateRecord?> loadRecord() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    final r = switch (decoded) {
      Map<String, dynamic> m => UsdtTwdRateRecord.fromJson(m),
      // 加同步之前只存一個數字；當成很舊的設定，雲端有就用雲端的。
      num v => UsdtTwdRateRecord(rate: v.toDouble(), updatedAt: DateTime(2000)),
      _ => null,
    };
    return r != null && r.rate > 0 ? r : null;
  }

  Future<double> load() async => (await loadRecord())?.rate ?? defaultRate;

  Future<void> save(double rate) =>
      saveRecord(UsdtTwdRateRecord(rate: rate, updatedAt: DateTime.now()));

  Future<void> saveRecord(UsdtTwdRateRecord record) =>
      _store.write(_key, jsonEncode(record.toJson()));
}

import '../storage/key_value_store.dart';

/// 交易&自律裡 USDT 換台幣用的匯率（2026-10-10 使用者要求：USDT 後面加上
/// 台幣換算，預設 31，設定可改）。存本機、跨裝置不同步，跟其他顯示用的
/// 設定一樣。
class UsdtTwdRateStore {
  UsdtTwdRateStore(this._store);

  static const _key = 'trade_log.usdt_twd_rate.v1';

  static const defaultRate = 31.0;

  final KeyValueStore _store;

  Future<double> load() async {
    final v = double.tryParse(await _store.read(_key) ?? '');
    return v == null || v <= 0 ? defaultRate : v;
  }

  Future<void> save(double rate) => _store.write(_key, '$rate');
}

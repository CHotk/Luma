import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 記帳的設定：虛擬貨幣 USDT 粗估換算台幣的匯率（2026-11-11 使用者：改用 32.6、設定內要可調整）。
/// 只用在沒填 USDT 的粗估跟「≈ 台幣」的顯示；有填的照填的算。跨裝置同步，見 [StampedSettingStore]。
class LedgerUsdtRateStore {
  LedgerUsdtRateStore(this._store);

  final KeyValueStore _store;

  static const _key = 'ledger.usdt_rate.v1';
  static const defaultValue = 32.6;

  /// 雲端上的檔名。
  static const cloudKey = 'ledger_usdt_rate.json';

  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<double> load() async {
    final v = double.tryParse(await record.loadValue() ?? '');
    return v == null || v <= 0 ? defaultValue : v;
  }

  Future<void> save(double value) => record.saveValue('$value');
}

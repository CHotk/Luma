import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 記帳的設定：要不要用「已確認」功能（2026-11-11 使用者：設定裡可以關掉，關了列表沒有小藍點、
/// 明細沒有確認鈕、篩選也沒有「未確認」）。預設開。跨裝置同步，見 [StampedSettingStore]。
class LedgerConfirmStore {
  LedgerConfirmStore(this._store);

  final KeyValueStore _store;

  static const _key = 'ledger.confirm_on.v1';
  static const defaultValue = true;

  /// 雲端上的檔名。
  static const cloudKey = 'ledger_confirm_on.json';

  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<bool> load() async {
    final v = await record.loadValue();
    return v == null ? defaultValue : v == 'true';
  }

  Future<void> save(bool value) => record.saveValue('$value');
}

import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 記帳的設定：金額剛好是 110 或 1100 時，記完問要不要把分類改成菸酒（2026-11-10 使用者）。
/// 預設開。跨裝置同步，見 [StampedSettingStore]。
class LedgerSinAskStore {
  LedgerSinAskStore(this._store);

  final KeyValueStore _store;

  static const _key = 'ledger.sin_ask.v1';
  static const defaultValue = true;

  /// 雲端上的檔名。
  static const cloudKey = 'ledger_sin_ask.json';

  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<bool> load() async {
    final v = await record.loadValue();
    return v == null ? defaultValue : v == 'true';
  }

  Future<void> save(bool value) => record.saveValue('$value');
}

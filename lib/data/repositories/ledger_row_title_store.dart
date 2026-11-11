import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 記帳的設定：列表每一條最大的那行字顯示什麼（2026-11-11 使用者：預設改顯示分類，設定內可改回
/// 商家）。`category`＝分類（預設）、`merchant`＝商家名稱。跨裝置同步，見 [StampedSettingStore]。
class LedgerRowTitleStore {
  LedgerRowTitleStore(this._store);

  final KeyValueStore _store;

  static const _key = 'ledger.row_title.v1';
  static const category = 'category';
  static const merchant = 'merchant';
  static const defaultValue = category;

  /// 雲端上的檔名。
  static const cloudKey = 'ledger_row_title.json';

  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<String> load() async {
    final v = await record.loadValue();
    return v == merchant ? merchant : defaultValue;
  }

  Future<void> save(String value) => record.saveValue(value);
}

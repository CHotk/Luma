import '../storage/key_value_store.dart';
import 'stamped_setting_store.dart';

/// 記帳的設定：最近記帳、明細每一條要不要顯示備註（2026-11-04 使用者）。
/// 預設顯示。跨裝置同步，見 [StampedSettingStore]。
class LedgerShowNoteStore {
  LedgerShowNoteStore(this._store);

  final KeyValueStore _store;

  static const _key = 'ledger.show_note.v1';
  static const defaultValue = true;

  /// 雲端上的檔名。
  static const cloudKey = 'ledger_show_note.json';

  StampedSettingStore get record =>
      StampedSettingStore(_store, key: _key, cloudKey: cloudKey);

  Future<bool> load() async {
    final v = await record.loadValue();
    return v == null ? defaultValue : v == 'true';
  }

  Future<void> save(bool value) => record.saveValue('$value');
}

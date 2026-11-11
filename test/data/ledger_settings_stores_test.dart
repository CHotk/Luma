import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/ledger_confirm_store.dart';
import 'package:lume/data/repositories/ledger_row_title_store.dart';
import 'package:lume/data/repositories/ledger_show_note_store.dart';
import 'package:lume/data/repositories/ledger_sin_ask_store.dart';
import 'package:lume/data/repositories/ledger_usdt_rate_store.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 記帳的設定（會同步）：沒存過用預設、存了讀回來、亂寫的值不會壞（邊界）。
void main() {
  test('顯示備註：預設開、可關', () async {
    final s = _MemoryStore();
    expect(await LedgerShowNoteStore(s).load(), isTrue);
    await LedgerShowNoteStore(s).save(false);
    expect(await LedgerShowNoteStore(s).load(), isFalse);
    expect(await LedgerShowNoteStore(s).record.loadRecord(), isNotNull);
  });

  test('110／1100 問要不要改菸酒：預設開、可關', () async {
    final s = _MemoryStore();
    expect(await LedgerSinAskStore(s).load(), isTrue);
    await LedgerSinAskStore(s).save(false);
    expect(await LedgerSinAskStore(s).load(), isFalse);
  });

  test('已確認功能：預設開、可關', () async {
    final s = _MemoryStore();
    expect(await LedgerConfirmStore(s).load(), isTrue);
    await LedgerConfirmStore(s).save(false);
    expect(await LedgerConfirmStore(s).load(), isFalse);
    await LedgerConfirmStore(s).save(true);
    expect(await LedgerConfirmStore(s).load(), isTrue);
  });

  test('列表大字：預設分類、可改商家；亂寫的值當預設', () async {
    final s = _MemoryStore();
    expect(await LedgerRowTitleStore(s).load(), LedgerRowTitleStore.category);
    await LedgerRowTitleStore(s).save(LedgerRowTitleStore.merchant);
    expect(await LedgerRowTitleStore(s).load(), LedgerRowTitleStore.merchant);
    await LedgerRowTitleStore(s).save('亂寫');
    expect(await LedgerRowTitleStore(s).load(), LedgerRowTitleStore.category);
  });

  test('USDT 匯率：預設 32.6、可改；0、負數、不是數字都當預設（邊界）', () async {
    final s = _MemoryStore();
    expect(await LedgerUsdtRateStore(s).load(), 32.6);
    await LedgerUsdtRateStore(s).save(31.5);
    expect(await LedgerUsdtRateStore(s).load(), 31.5);
    await LedgerUsdtRateStore(s).save(0);
    expect(await LedgerUsdtRateStore(s).load(), 32.6);
    await LedgerUsdtRateStore(s).save(-3);
    expect(await LedgerUsdtRateStore(s).load(), 32.6);
    await LedgerUsdtRateStore(s).record.saveValue('abc');
    expect(await LedgerUsdtRateStore(s).load(), 32.6);
  });

  test('每個設定的雲端檔名都不一樣（不會互相蓋掉）', () {
    final keys = {
      LedgerShowNoteStore.cloudKey,
      LedgerSinAskStore.cloudKey,
      LedgerConfirmStore.cloudKey,
      LedgerRowTitleStore.cloudKey,
      LedgerUsdtRateStore.cloudKey,
    };
    expect(keys.length, 5);
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';

/// 沒有「購物」分類了；設定裡的「購物併入生活」把舊資料轉到生活。
void main() {
  test('分類清單沒有購物', () {
    expect(ledgerExpenseCats.containsKey('購物'), isFalse);
    expect(ledgerExpenseCats.containsKey('生活'), isTrue);
  });

  test('購物的交易（含拆分的一份）、預算都併到生活，其他不動，記進操作紀錄', () async {
    final repo = LedgerRepository(_MemoryStore());
    final acct = (await repo.loadBook()).accounts.first;
    LedgerTx tx(String id, String cat, {List<LedgerSplit>? splits}) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 2, 12),
      amount: 100,
      accountId: acct.id,
      category: cat,
      merchant: id,
      splits: splits ?? const [],
    );
    await repo.addTransaction(tx('shop', '購物'));
    await repo.addTransaction(tx('food', '餐飲'));
    await repo.addTransaction(
      tx(
        'mix',
        '購物',
        splits: const [
          LedgerSplit(category: '購物', amount: 60),
          LedgerSplit(category: '餐飲', amount: 40),
        ],
      ),
    );
    await repo.setBudgets('2026-11', 0, {'生活': 1000});
    // 直接寫一筆舊的購物預算（現在畫面已經設不到購物了）。
    final all = await repo.budgetsForUpload();
    await repo.mergeBudgetsFromCloud([
      LedgerBudget(
        month: '2026-11',
        category: '購物',
        amount: 500,
        updatedAt: DateTime.now().add(const Duration(seconds: 1)),
      ),
    ]);
    expect(all.any((b) => b.category == '購物'), isFalse);

    final n = await repo.moveShoppingToLife();
    expect(n, 3); // 2 筆交易＋1 個月預算

    final book = await repo.loadBook();
    expect(book.txs.firstWhere((t) => t.merchant == 'shop').category, '生活');
    expect(book.txs.firstWhere((t) => t.merchant == 'food').category, '餐飲');
    final mix = book.txs.firstWhere((t) => t.merchant == 'mix');
    expect(mix.category, '生活');
    expect(mix.splits.map((s) => s.category), ['生活', '餐飲']);
    expect(mix.splits.map((s) => s.amount), [60, 40]);
    expect(book.statsWhere((t) => true).byCategory.containsKey('購物'), isFalse);

    // 預算併進生活：1000 + 500，購物的蓋墓碑。
    final budgets = await repo.budgetsForUpload();
    expect(
      budgets
          .firstWhere((b) => b.category == '生活' && b.deletedAt == null)
          .amount,
      1500,
    );
    expect(budgets.firstWhere((b) => b.category == '購物').deletedAt, isNotNull);

    final log = await repo.logForUpload();
    expect(log.any((e) => e.action == '購物併入生活'), isTrue);

    // 再按一次：沒有東西可轉。
    expect(await repo.moveShoppingToLife(), 0);
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

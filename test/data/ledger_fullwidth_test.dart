import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';

/// 設定裡的「整理全形文字」：把已經記的全形英數字一次改成半形小寫
/// （ＦＯＯＤＰＡＮＤＡ → foodpanda），中文跟沒全形字的紀錄一個字都不碰。
void main() {
  test('舊資料的全形英數字全部改成半形小寫，其他不動，記進操作紀錄', () async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final card = await repo.addAccount(
      name: 'ＣＴＢＣ　卡',
      type: LedgerAccountType.creditCard,
    );
    final plain = await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
    );
    final old = DateTime(2026, 11, 1, 9);
    final dirty = LedgerTx(
      id: ledgerId(),
      type: LedgerTxType.expense,
      occurredAt: old,
      amount: 500,
      accountId: card.id,
      category: '餐飲',
      merchant: 'ＦＯＯＤＰＡＮＤＡ　',
      note: '外送，ＵＢＥＲ　Ｅａｔｓ（１２３）',
      paidFor: const PaidFor(amount: 250, people: 'Ｃｅｎ'),
      splits: const [
        LedgerSplit(category: '餐飲', amount: 300, name: 'ＢＵＲＧＥＲ'),
        LedgerSplit(
          category: '生活',
          amount: 200,
          name: '衛生紙',
          forOther: true,
          people: 'Ｃｅｎ',
        ),
      ],
      updatedAt: old,
    );
    final clean = LedgerTx(
      id: ledgerId(),
      type: LedgerTxType.expense,
      occurredAt: old,
      amount: 100,
      accountId: plain.id,
      category: '餐飲',
      merchant: 'FoodPanda，鼎泰豐',
      note: '正常（不要動）',
      updatedAt: old,
    );
    await repo.addTransactions([dirty, clean]);
    final sub = await repo.addSubscription(
      name: 'ＮＥＴＦＬＩＸ',
      amount: 390,
      day: 12,
      note: '家庭方案ＸＬ',
    );
    final logBefore = (await repo.loadLog()).length;
    final before = await repo.loadBook();
    final cleanStamp = before.tx(clean.id)!.updatedAt;
    final dirtyStamp = before.tx(dirty.id)!.updatedAt!;

    final n = await repo.normalizeFullWidthText();
    final book = await repo.loadBook();
    final d = book.tx(dirty.id)!;
    expect(d.merchant, 'foodpanda');
    expect(d.note, '外送，uber eats（123）');
    expect(d.paidFor!.people, 'cen');
    expect(d.paidFor!.amount, 250);
    expect(d.splits.map((s) => s.name), ['burger', '衛生紙']);
    expect(d.splits.map((s) => s.people), ['', 'cen']);
    expect(d.splits.map((s) => s.forOther), [false, true]);
    expect(d.splits.map((s) => s.amount), [300, 200]);
    expect(d.updatedAt!.isAfter(dirtyStamp), isTrue); // 同步才會帶到其他裝置
    // 沒有全形字的那筆原封不動（連 updatedAt 都沒動）。
    final c = book.tx(clean.id)!;
    expect(c.merchant, 'FoodPanda，鼎泰豐');
    expect(c.note, '正常（不要動）');
    expect(c.updatedAt, cleanStamp);
    // 帳戶、訂閱。
    expect(book.accountName(card.id), 'ctbc 卡');
    expect(book.accountName(plain.id), '現金');
    final s = (await repo.loadSubscriptions()).firstWhere(
      (x) => x.id == sub.id,
    );
    expect(s.name, 'netflix');
    expect(s.note, '家庭方案xl');
    // 回傳 = 改了幾筆（1 交易 + 1 帳戶 + 1 訂閱）。
    expect(n, 3);
    // 操作紀錄多一筆，寫出舊 → 新。
    final log = await repo.loadLog();
    expect(log.length, logBefore + 1);
    final entry = log.firstWhere((e) => e.action == '整理全形文字');
    expect(entry.summary, '改了 1 筆交易、1 個帳戶、1 個訂閱');
    expect(entry.detail, contains('商家：ＦＯＯＤＰＡＮＤＡ　 → foodpanda'));
    expect(entry.detail, contains('帳戶名稱：ＣＴＢＣ　卡 → ctbc 卡'));
    // 再按一次：沒東西可改，回 0，不多記一筆。
    expect(await repo.normalizeFullWidthText(), 0);
    expect((await repo.loadLog()).length, logBefore + 1);
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

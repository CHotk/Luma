import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';

/// 拆分的一份幫人付可以只給一部分（一人一半）：自己的消費只扣對方要給的那段。
void main() {
  test('一份 500 幫人付、對方給 250：這份自己 250；不填金額＝整份都是對方的', () {
    const half = LedgerSplit(
      category: '餐飲',
      amount: 500,
      forOther: true,
      people: 'Cen',
      otherAmount: 250,
    );
    expect(half.otherPart, 250);
    expect(half.ownPart, 250);
    const all = LedgerSplit(category: '餐飲', amount: 500, forOther: true);
    expect(all.otherPart, 500);
    expect(all.ownPart, 0);
    // 沒標幫人付：金額欄位不管用。
    const none = LedgerSplit(category: '餐飲', amount: 500, otherAmount: 100);
    expect(none.otherPart, 0);
    // 超過這份的金額就收在這份的金額。
    const over = LedgerSplit(
      category: '餐飲',
      amount: 500,
      forOther: true,
      otherAmount: 900,
    );
    expect(over.otherPart, 500);
  });

  test('JSON 來回：只給一部分才存 otherAmount，整份不存；舊資料照讀', () {
    const half = LedgerSplit(
      category: '餐飲',
      amount: 500,
      forOther: true,
      otherAmount: 250,
    );
    expect(half.toJson()['otherAmount'], 250);
    expect(LedgerSplit.fromJson(half.toJson()).otherAmount, 250);
    const full = LedgerSplit(
      category: '餐飲',
      amount: 500,
      forOther: true,
      otherAmount: 500,
    );
    expect(full.toJson().containsKey('otherAmount'), isFalse);
    expect(
      LedgerSplit.fromJson({'category': '餐飲', 'amount': 500}).otherAmount,
      isNull,
    );
  });

  test('統計：另一份 500 一人一半，這筆自己的消費是 750，各分類照這個算', () {
    final tx = LedgerTx(
      id: 't',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 3, 12),
      amount: 1000,
      accountId: 'a',
      category: '餐飲',
      splits: const [
        LedgerSplit(category: '生活', amount: 500),
        LedgerSplit(
          category: '餐飲',
          amount: 500,
          forOther: true,
          people: 'Cen',
          otherAmount: 250,
        ),
      ],
      paidFor: const PaidFor(amount: 250, people: 'Cen'),
    );
    expect(tx.ownSpend, 750);
    final book = LedgerBook(
      accounts: [
        LedgerAccount(id: 'a', name: '現金', type: LedgerAccountType.cash),
      ],
      txs: [tx],
      checkpoints: const [],
      budgets: const [],
    );
    final st = book.statsWhere((x) => x.id == 't');
    expect(st.spend, 750);
    expect(st.byCategory['生活'], 500);
    expect(st.byCategory['餐飲'], 250);
    // 外面標已給，每一份的金額設定保留。
    expect(tx.withSettled(true).splits[1].otherAmount, 250);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_row_title_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_ui.dart';

/// 列表一條的顯示邊界（2026-11-12 使用者：涵蓋率補到 95%、更多邊界）：USDT 小數、
/// 「多久以前」、每種類型的圖示、品牌圖示（錢從哪裡出去）、列表大字、虛擬貨幣盈虧標籤。
void main() {
  const bank = LedgerAccount(
    id: 'bank',
    name: '中信活存',
    type: LedgerAccountType.bank,
    order: 1,
  );
  const cash = LedgerAccount(
    id: 'cash',
    name: '現金',
    type: LedgerAccountType.cash,
    order: 2,
  );
  final at = DateTime(2026, 10, 5, 12);
  LedgerBook book(List<LedgerTx> txs) => LedgerBook(
    accounts: const [bank, cash],
    txs: txs,
    checkpoints: [
      LedgerCheckpoint(
        id: 'o',
        accountId: 'bank',
        at: DateTime(2026, 10, 1),
        balance: 10000,
      ),
    ],
    budgets: const [],
  );
  LedgerTx t(
    LedgerTxType type, {
    String id = 'x',
    String account = 'bank',
    String? to,
    String? category,
    String merchant = '',
    String toName = '',
    String fromName = '',
    bool toOther = false,
    List<LedgerSplit> splits = const [],
    double? usdt,
    double? toAfter,
    double? fromAfter,
    bool pnlOk = false,
    String? dir,
    String source = 'manual',
    DateTime? when,
  }) => LedgerTx(
    id: id,
    type: type,
    occurredAt: when ?? at,
    amount: 3260,
    accountId: account,
    toAccountId: to,
    category: category,
    merchant: merchant,
    toName: toName,
    fromName: fromName,
    toOther: toOther,
    splits: splits,
    extAmount: usdt,
    toAfter: toAfter,
    fromAfter: fromAfter,
    extPnlOk: pnlOk,
    dir: dir,
    source: source,
  );

  test('USDT：整數、一位、兩位小數', () {
    expect(lUsdt(100), '100');
    expect(lUsdt(12.5), '12.5');
    expect(lUsdt(12.34), '12.34');
    expect(lUsdt(0.001), '0');
  });

  test('多久以前：剛剛、分鐘、小時、天', () {
    final now = DateTime.now();
    expect(lAgo(now), '剛剛');
    expect(lAgo(now.subtract(const Duration(minutes: 5))), '5 分鐘前');
    expect(lAgo(now.subtract(const Duration(hours: 3))), '3 小時前');
    expect(lAgo(now.subtract(const Duration(days: 2))), '2 天前');
  });

  test('圖示：沒有的分類用未分類／其他收入；ATM 提款 🏧；其他類型各自的符號', () {
    final b = book(const []);
    expect(txLook(t(LedgerTxType.expense, category: '不存在')).$1, isNotEmpty);
    expect(txLook(t(LedgerTxType.income, category: '不存在')).$1, isNotEmpty);
    expect(txLook(t(LedgerTxType.transfer, to: 'cash'), b).$1, '🏧');
    expect(txLook(t(LedgerTxType.transfer, to: 'cash')).$1, '⇄');
    expect(txLook(t(LedgerTxType.refund)).$1, '↩️');
    expect(txLook(t(LedgerTxType.repayment)).$1, '🤝');
    expect(txLook(t(LedgerTxType.adjustment)).$1, '⚖️');
    expect(catLook(ledgerToOtherCat).$1, '👤');
    expect(catLook(ledgerPaidForOut).$1, '👥');
    expect(catLook('完全沒有這個').$1, isNotEmpty);
  });

  test('品牌圖示：從 LineBank 轉出＝LINE Bank、從富邦轉出＝沒有；收入平轉看從哪來', () {
    final b = book(const []);
    expect(
      ledgerBrandOf(
        b,
        t(LedgerTxType.transfer, account: '', fromName: 'LineBank'),
      )!.asset,
      contains('linebank'),
    );
    expect(
      ledgerBrandOf(b, t(LedgerTxType.transfer, account: '', fromName: '富邦')),
      isNull,
    );
    expect(
      ledgerBrandOf(
        b,
        t(
          LedgerTxType.income,
          category: ledgerFlatTransfer,
          toName: 'LineBank',
        ),
      )!.asset,
      contains('linebank'),
    );
    expect(
      ledgerBrandOf(
        b,
        t(LedgerTxType.income, category: ledgerFlatTransfer, toName: '富邦'),
      ),
      isNull,
    );
    expect(
      ledgerBrandOf(b, t(LedgerTxType.transfer, to: 'cash'))!.asset,
      contains('atm'),
    );
  });

  test('列表大字：拆分寫分類＋分類、轉給他人、平轉沒名稱寫類型、退款等寫類型', () {
    expect(
      ledgerRowTitle(
        t(
          LedgerTxType.expense,
          splits: const [
            LedgerSplit(category: '餐飲', amount: 1),
            LedgerSplit(category: '餐飲', amount: 1),
            LedgerSplit(category: '交通', amount: 1),
          ],
        ),
      ),
      '餐飲＋交通',
    );
    expect(ledgerRowTitle(t(LedgerTxType.expense)), ledgerUncategorized);
    expect(
      ledgerRowTitle(t(LedgerTxType.transfer, toOther: true)),
      ledgerToOtherCat,
    );
    expect(
      ledgerRowTitle(
        t(
          LedgerTxType.transfer,
          toOther: true,
          splits: const [
            LedgerSplit(category: '娛樂', amount: 1),
            LedgerSplit(category: '餐飲', amount: 1),
          ],
        ),
      ),
      '娛樂＋餐飲',
    );
    expect(
      ledgerRowTitle(t(LedgerTxType.transfer)),
      LedgerTxType.transfer.label,
    );
    expect(ledgerRowTitle(t(LedgerTxType.transfer, merchant: '繳卡費')), '繳卡費');
    expect(ledgerRowTitle(t(LedgerTxType.refund)), LedgerTxType.refund.label);
    expect(
      ledgerRowTitle(t(LedgerTxType.adjustment)),
      LedgerTxType.adjustment.label,
    );
  });

  Future<void> pumpTile(
    WidgetTester tester,
    LedgerBook b,
    LedgerTx x, {
    String title = LedgerRowTitleStore.category,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerRowTitleProvider.overrideWith((_) => title)],
        child: MaterialApp(
          home: Scaffold(
            body: TxTile(book: b, tx: x, onTap: () {}, showDate: true),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('虛擬貨幣差額：沒確認＝⚠ 提醒；確認了＝盈利／虧損', (tester) async {
    final first = t(
      LedgerTxType.transfer,
      id: 'c1',
      toName: ledgerCryptoExt,
      usdt: 100,
      toAfter: 100,
      when: at,
    );
    LedgerTx second(double after, bool ok) => t(
      LedgerTxType.transfer,
      id: 'c2',
      toName: ledgerCryptoExt,
      usdt: 100,
      toAfter: after,
      pnlOk: ok,
      when: at.add(const Duration(days: 1)),
    );
    for (final (after, ok, text) in [
      (210.0, false, '⚠ 虛擬貨幣差 +10 USDT'),
      (210.0, true, '盈利 +10 USDT'),
      (190.0, true, '虧損 −10 USDT'),
    ]) {
      final s = second(after, ok);
      await pumpTile(tester, book([first, s]), s);
      expect(find.textContaining(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('轉帳一條：拆分、花掉的部分、平轉、轉給他人、USDT；調整有外框；匯入有標籤', (tester) async {
    final b = book(const []);
    final cases = <(LedgerTx, String)>[
      (
        t(
          LedgerTxType.transfer,
          to: 'cash',
          splits: const [LedgerSplit(category: '餐飲', amount: 500, name: '便當')],
        ),
        '含花費',
      ),
      (t(LedgerTxType.transfer, toName: 'LineBank', usdt: 3), '平轉'),
      (t(LedgerTxType.transfer, toOther: true, toName: '小美'), '轉給他人'),
      (t(LedgerTxType.transfer, to: 'cash'), '不算支出'),
      (t(LedgerTxType.adjustment, dir: 'in'), '對帳調整'),
      (t(LedgerTxType.expense, category: '餐飲', source: 'paste'), '匯入'),
    ];
    for (final (x, text) in cases) {
      await pumpTile(tester, b, x);
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    // 大字顯示商家（設定改的）：小字是品項。
    await pumpTile(
      tester,
      b,
      t(LedgerTxType.expense, category: '餐飲', merchant: '麥當勞'),
      title: LedgerRowTitleStore.merchant,
    );
    expect(find.textContaining('麥當勞'), findsWidgets);
  });
}

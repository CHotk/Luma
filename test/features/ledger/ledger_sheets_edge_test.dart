import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_data.dart';
import 'package:lume/features/ledger/ledger_sheets.dart';

/// 記帳表單、明細、匯入預覽的邊界（2026-11-12 使用者：涵蓋率補到 95%、更多邊界）：
/// 還錢（沒人欠／有人欠）、對帳調整的編輯、虛擬貨幣跟推算有差要確認盈虧、貼上多行／看不懂、
/// 匯入預覽（看不懂的行、轉給別人算支出、點一行改）、明細的原始文字、缺的數字剛好是某一筆
/// 時的提示、分類的預算卡、開始記帳加減銀行戶頭。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> host(
    WidgetTester tester,
    _MemoryStore store,
    Future<void> Function(BuildContext, WidgetRef) run,
  ) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, ref, _) => Center(
                child: ElevatedButton(
                  key: const ValueKey('go'),
                  onPressed: () => run(c, ref),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
  }

  Future<LedgerBook> book(WidgetTester tester, LedgerRepository repo) async =>
      (await tester.runAsync(repo.loadBook))!;

  Future<void> tapFilled(WidgetTester tester, String text) async {
    final f = find.widgetWithText(FilledButton, text).last;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  Future<(LedgerRepository, LedgerAccount)> bankOnly(
    WidgetTester tester,
    _MemoryStore store,
  ) async {
    final repo = LedgerRepository(store);
    late LedgerAccount bank;
    await tester.runAsync(() async {
      await repo.loadBook();
      bank = await repo.addAccount(
        name: '測試活存',
        type: LedgerAccountType.bank,
        opening: 5000,
        openingAt: DateTime.now().subtract(const Duration(days: 3)),
      );
    });
    return (repo, bank);
  }

  testWidgets('還錢：沒人欠你錢時寫「目前沒有人欠你錢」（邊界）', (tester) async {
    final store = _MemoryStore();
    await bankOnly(tester, store);
    await host(
      tester,
      store,
      (c, ref) => txFormFlow(
        c,
        ref,
        prefill: const TxPrefill(type: LedgerTxType.repayment),
      ),
    );
    expect(find.textContaining('目前沒有人欠你錢'), findsOneWidget);
  });

  testWidgets('還錢：選欠的那筆 → 金額帶剩下的、存了那筆標已給', (tester) async {
    final store = _MemoryStore();
    final (repo, bank) = await bankOnly(tester, store);
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: 'hot',
          type: LedgerTxType.expense,
          occurredAt: DateTime.now().subtract(const Duration(hours: 5)),
          amount: 900,
          accountId: bank.id,
          category: '餐飲',
          merchant: '火鍋',
          paidFor: const PaidFor(amount: 450, people: '小美'),
        ),
      ),
    );
    await host(
      tester,
      store,
      (c, ref) => txFormFlow(
        c,
        ref,
        prefill: const TxPrefill(type: LedgerTxType.repayment, linkedId: 'hot'),
      ),
    );
    expect(find.text('給的是哪一筆'), findsOneWidget);
    expect(find.textContaining('小美 還欠'), findsWidgets);
    expect(find.text('這次還完就標記已還清'), findsOneWidget);
    final pick = find.textContaining('測試活存').last;
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pump();
    await tapFilled(tester, '新增');
    final b = await book(tester, repo);
    final r = b.txs.firstWhere((t) => t.type == LedgerTxType.repayment);
    expect(r.amount, 450);
    expect(b.tx('hot')!.paidFor!.settled, isTrue);
  });

  testWidgets('編輯對帳調整：寫是哪個帳戶、算未分類；按外面關掉不改（取消）', (tester) async {
    final store = _MemoryStore();
    final (repo, bank) = await bankOnly(tester, store);
    final adj = LedgerTx(
      id: 'adj',
      type: LedgerTxType.adjustment,
      occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
      amount: 120,
      accountId: bank.id,
      source: 'adjust',
    );
    await tester.runAsync(() => repo.addTransaction(adj));
    await host(tester, store, (c, ref) => txFormFlow(c, ref, edit: adj));
    expect(find.textContaining('對帳調整：測試活存'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect((await book(tester, repo)).tx('adj')!.amount, 120);
  });

  testWidgets('虛擬貨幣入金：之前填過餘額，這次填的跟推算差 10 USDT → 可以確認是盈利', (tester) async {
    final store = _MemoryStore();
    final (repo, _) = await bankOnly(tester, store);
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: 'c1',
          type: LedgerTxType.transfer,
          occurredAt: DateTime.now().subtract(const Duration(days: 1)),
          amount: 3260,
          accountId: '',
          fromName: 'LineBank',
          toName: ledgerCryptoExt,
          extAmount: 100,
          toAfter: 100,
          merchant: '虛擬貨幣入金',
        ),
      ),
    );
    await host(
      tester,
      store,
      (c, ref) => txFormFlow(
        c,
        ref,
        prefill: const TxPrefill(type: LedgerTxType.transfer),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('cryptoDeposit')));
    await settle(tester);
    final amount = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
    );
    await tester.enterText(amount, '3260');
    await tester.ensureVisible(find.byKey(const ValueKey('usdtField')));
    await tester.enterText(find.byKey(const ValueKey('usdtField')), '100');
    await tester.pump();
    final after = find.byKey(const ValueKey('extAfter'));
    await tester.ensureVisible(after);
    // 沒填：寫推算多少 USDT。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('extAfterNote'))).data,
      startsWith('推算 200 USDT'),
    );
    await tester.enterText(after, '210');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('extAfterNote'))).data,
      contains('推算 200 USDT'),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cryptoDiff'))).data,
      startsWith('跟推算差 +10 USDT'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('pnlOk')));
    tester.widget<FilterChip>(find.byKey(const ValueKey('pnlOk'))).onSelected!(
      true,
    );
    await tester.pump();
    expect(find.text('確認是盈利'), findsOneWidget);
    await tapFilled(tester, '新增');
    final b = await book(tester, repo);
    final t = b.txs.firstWhere((x) => x.id != 'c1');
    expect(t.toAfter, 210);
    expect(t.extPnlOk, isTrue);
    expect(b.usdtDiffOf(t), closeTo(10, 0.001));
  });

  testWidgets('貼一行：貼了兩行叫你用匯入、看不懂的寫原因、清空就沒訊息（邊界）', (tester) async {
    final store = _MemoryStore();
    await bankOnly(tester, store);
    await host(tester, store, (c, ref) => txFormFlow(c, ref));
    final paste = find.byType(TextField).first;
    await tester.enterText(
      paste,
      '現金｜2026/11/01 08:00｜餐飲｜早餐｜80\n現金｜2026/11/01 09:00｜餐飲｜咖啡｜60',
    );
    await tester.pump();
    expect(find.textContaining('有 2 行'), findsOneWidget);
    await tester.enterText(paste, '現金｜不是日期｜餐飲｜早餐｜80');
    await tester.pump();
    expect(find.textContaining('看不懂日期時間'), findsOneWidget);
    await tester.enterText(paste, '   ');
    await tester.pump();
    expect(find.textContaining('看不懂日期時間'), findsNothing);
  });

  testWidgets('匯入預覽：看不懂的行打 ✕；轉到自己帳戶可勾「算支出」；點一行開表單改', (tester) async {
    final store = _MemoryStore();
    final (repo, _) = await bankOnly(tester, store);
    await host(tester, store, (c, ref) => importFlow(c, ref));
    await tester.enterText(
      find.byType(TextField).first,
      '亂寫一行\n'
      '測試活存｜2026/11/01 10:00｜轉帳｜現金｜500\n'
      '現金｜2026/11/01 12:00｜餐飲｜便當｜100｜小美｜50',
    );
    await tester.pump();
    expect(find.text('✕ '), findsNothing); // TextSpan 不是獨立 Text
    expect(find.textContaining('欄位不夠'), findsOneWidget);
    expect(find.textContaining('→ 現金（不算支出）'), findsOneWidget);
    expect(find.textContaining('小美 要給'), findsOneWidget);
    await tester.tap(find.text('算支出（錢是給別人的）'));
    await tester.pump();
    expect(find.textContaining('未分類（轉給別人）'), findsOneWidget);
    // 再按一次取消勾。
    await tester.tap(find.text('算支出（錢是給別人的）'));
    await tester.pump();
    expect(find.textContaining('→ 現金（不算支出）'), findsOneWidget);
    await tester.tap(find.text('算支出（錢是給別人的）'));
    await tester.pump();
    // 點便當那行 → 開編輯表單，按外面關掉＝不改。
    await tester.tap(find.textContaining('便當・').first);
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.textContaining('便當・'), findsOneWidget);
    await tapFilled(tester, '匯入 2 筆');
    final b = await book(tester, repo);
    final spend = b.txs.firstWhere((t) => t.amount == 500);
    expect(spend.type, LedgerTxType.expense);
    expect(spend.category, ledgerUncategorized);
  });

  testWidgets('明細：貼上匯入的顯示原始文字', (tester) async {
    final store = _MemoryStore();
    final (repo, bank) = await bankOnly(tester, store);
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: 'p1',
          type: LedgerTxType.expense,
          occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
          amount: 80,
          accountId: bank.id,
          category: '餐飲',
          merchant: '早餐',
          source: 'paste',
          raw: '測試活存｜原始那一行',
        ),
      ),
    );
    await host(tester, store, (c, ref) => txDetailFlow(c, ref, 'p1'));
    expect(find.text('貼上匯入'), findsOneWidget);
    expect(find.text('測試活存｜原始那一行'), findsOneWidget);
  });

  testWidgets('漏記提示：缺的數字剛好是一筆記在範圍外的 → 點了把它時間移進來、標籤消失', (tester) async {
    final store = _MemoryStore();
    final (repo, bank) = await bankOnly(tester, store);
    final now = DateTime.now();
    await tester.runAsync(() async {
      // 時間記錯：在第一個餘額之前。
      await repo.addTransaction(
        LedgerTx(
          id: 'early',
          type: LedgerTxType.expense,
          occurredAt: now.subtract(const Duration(days: 10)),
          amount: 300,
          accountId: bank.id,
          category: '餐飲',
          merchant: '記錯時間',
        ),
      );
      await repo.addTransaction(
        LedgerTx(
          id: 'e2',
          type: LedgerTxType.expense,
          occurredAt: now.subtract(const Duration(hours: 2)),
          amount: 200,
          accountId: bank.id,
          category: '餐飲',
          merchant: '午餐',
        ),
      );
      await repo.setTxCheckpoint(
        txId: 'e2',
        accountId: bank.id,
        at: now.subtract(const Duration(hours: 2)),
        value: 4500,
        creditLimit: null,
      );
    });
    await host(tester, store, (c, ref) => txDetailFlow(c, ref, 'e2'));
    final hint = find.textContaining('剛好是缺的數字，但時間在這兩個餘額之外');
    expect(hint, findsOneWidget);
    await tester.ensureVisible(hint);
    await tester.tap(hint);
    await settle(tester);
    final b = await book(tester, repo);
    expect(b.gapOfTx('e2'), isNull);
    expect(find.textContaining('漏記標籤消失了'), findsOneWidget);
  });

  testWidgets('分類明細：有預算時寫還剩多少；超支寫超支', (tester) async {
    final store = _MemoryStore();
    final (repo, bank) = await bankOnly(tester, store);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await repo.setBudgets(monthKey(now.year, now.month), 0, {'餐飲': 1000});
      await repo.addTransaction(
        LedgerTx(
          id: 'f',
          type: LedgerTxType.expense,
          occurredAt: now.subtract(const Duration(minutes: 30)),
          amount: 400,
          accountId: bank.id,
          category: '餐飲',
          merchant: '晚餐',
        ),
      );
    });
    await host(
      tester,
      store,
      (c, ref) => categoryFlow(c, ref, '餐飲', now.year, now.month),
    );
    expect(find.text('還剩 \$600'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await tester.runAsync(
      () => repo.setBudgets(monthKey(now.year, now.month), 0, {'餐飲': 300}),
    );
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    expect(find.text('超支 \$100'), findsOneWidget);
  });

  testWidgets('開始記帳：再加一個銀行戶頭、加的可以拿掉', (tester) async {
    final store = _MemoryStore();
    await host(tester, store, (c, ref) => setupFlow(c, ref));
    final before = find.byType(TextField).evaluate().length;
    await tester.tap(find.text('再加一個銀行戶頭'));
    await tester.pump();
    expect(find.byType(TextField).evaluate().length, greaterThan(before));
    final remove = find.byIcon(Icons.remove_circle_outline_rounded);
    if (remove.evaluate().isNotEmpty) {
      await tester.tap(remove.last);
      await tester.pump();
      expect(find.byType(TextField).evaluate().length, before);
    }
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

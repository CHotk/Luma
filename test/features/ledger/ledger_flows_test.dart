import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_data.dart';

/// 記帳的每個操作流程（ledger_data.dart）從頭走到存檔：建帳戶、新增帳戶、對帳（第一次填、
/// 有差額→補記／直接調整、一次對帳全部帳戶、信用卡）、帳戶明細（改名、刪對帳、刪帳戶）、
/// 預算、匯入、🚩 清單、幫誰付過、分類明細、交易明細的每個動作（標記、確認、退款、他給了、
/// 刪除）。2026-11-11 使用者：記帳系統複雜，測試要完整、涵蓋率超過九成、包含邊界。
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

  /// 一顆按鈕，按了跑 [run]（某個流程）。
  Future<(LedgerRepository, _MemoryStore)> host(
    WidgetTester tester,
    Future<void> Function(BuildContext, WidgetRef) run, {
    _MemoryStore? store,
  }) async {
    final s = store ?? _MemoryStore();
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(s)],
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
    return (LedgerRepository(s), s);
  }

  Future<void> go(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
  }

  Future<LedgerBook> book(WidgetTester tester, LedgerRepository repo) async =>
      (await tester.runAsync(repo.loadBook))!;

  Finder fieldIn(String label) => find
      .descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(TextField),
      )
      .first;

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).last;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> tapFilled(WidgetTester tester, String text) async {
    final f = find.widgetWithText(FilledButton, text).last;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  // ── 建帳戶、新增帳戶 ──

  testWidgets('新增帳戶：選現金、填名稱跟餘額 → 存起來、有第一個餘額', (tester) async {
    late LedgerRepository repo;
    (repo, _) = await host(tester, (c, ref) => addAccountFlow(c, ref));
    await go(tester);
    expect(find.text('新增帳戶'), findsWidgets);
    // 沒填名稱不能新增（邊界）。
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.textContaining('現金').first);
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '零錢包');
    await tester.enterText(fields.at(1), '300');
    await tester.pump();
    await tapFilled(tester, '新增');
    final b = await book(tester, repo);
    final a = b.accounts.firstWhere((x) => x.name == '零錢包');
    expect(a.type, LedgerAccountType.cash);
    expect(b.stateOf(a)!.now, 300);
    expect(find.textContaining('已新增帳戶：零錢包'), findsOneWidget);
  });

  testWidgets('新增帳戶：按外面關掉＝不新增（取消）', (tester) async {
    late LedgerRepository repo;
    (repo, _) = await host(tester, (c, ref) => addAccountFlow(c, ref));
    final before = (await book(tester, repo)).accounts.length;
    await go(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect((await book(tester, repo)).accounts.length, before);
  });

  testWidgets('開始記帳：按「開始」把列出的帳戶都建起來', (tester) async {
    late LedgerRepository repo;
    (repo, _) = await host(tester, (c, ref) => setupFlow(c, ref));
    await go(tester);
    expect(find.text('開始記帳'), findsOneWidget);
    await tapFilled(tester, '開始');
    final b = await book(tester, repo);
    expect(b.accounts, isNotEmpty);
    expect(find.textContaining('開始記帳了'), findsOneWidget);
  });

  // ── 對帳 ──

  testWidgets('對帳：第一次填餘額＝從現在開始算，不比差額', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final acc = await repo.addAccount(name: '郵局', type: LedgerAccountType.bank);
    await host(tester, (c, ref) => reconFlow(c, ref, acc), store: store);
    await go(tester);
    expect(find.text('填餘額：郵局'), findsOneWidget);
    // 沒填數字不能按（邊界）。
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '記下來'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).last, '12345');
    await tester.pump();
    await tapFilled(tester, '記下來');
    final b = await book(tester, repo);
    expect(b.stateOf(b.account(acc.id)!)!.now, 12345);
    expect(find.textContaining('已記下郵局的餘額'), findsOneWidget);
  });

  Future<(LedgerRepository, _MemoryStore, LedgerAccount)> withSpend(
    WidgetTester tester,
  ) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final acc = await repo.addAccount(
      name: '郵局',
      type: LedgerAccountType.bank,
      opening: 5000,
      openingAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    await repo.addTransaction(
      LedgerTx(
        id: 'e1',
        type: LedgerTxType.expense,
        occurredAt: DateTime.now().subtract(const Duration(days: 1)),
        amount: 300,
        accountId: acc.id,
        category: '餐飲',
        merchant: '早餐',
      ),
    );
    return (repo, store, acc);
  }

  testWidgets('對帳有差額（少了 200）→ 直接調成未分類 → 再看結果對上了 → 完成', (tester) async {
    final (repo, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => reconFlow(c, ref, acc), store: store);
    await go(tester);
    expect(find.text('對帳：郵局'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '4500');
    await tester.pump();
    expect(find.textContaining('少了'), findsWidgets);
    await tapFilled(tester, '確認對帳');
    expect(find.text('對帳結果：郵局'), findsOneWidget);
    expect(find.textContaining('總共差'), findsOneWidget);
    await tapText(tester, '直接調成一筆未分類支出 \$200');
    final b = await book(tester, repo);
    final adj = b.txs.firstWhere((t) => t.type == LedgerTxType.adjustment);
    expect(adj.amount, 200);
    expect(adj.isAdjustOut, isTrue);
    expect(b.stateOf(b.account(acc.id)!)!.miss, 0);
    // 調完回到結果：對上了。
    expect(find.text('對上了！'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(find.text('對帳結果：郵局'), findsNothing);
  });

  testWidgets('對帳多了錢（多 100）→ 調整是「進來」的', (tester) async {
    final (repo, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => reconFlow(c, ref, acc), store: store);
    await go(tester);
    await tester.enterText(find.byType(TextField).last, '4800');
    await tester.pump();
    await tapFilled(tester, '確認對帳');
    expect(find.textContaining('可能有收入或退款沒記到'), findsOneWidget);
    await tapText(tester, '直接調成一筆未分類 +\$100');
    final adj = (await book(
      tester,
      repo,
    )).txs.firstWhere((t) => t.type == LedgerTxType.adjustment);
    expect(adj.dir, 'in');
    expect(adj.amount, 100);
  });

  testWidgets('對帳有差額 → 補記一筆：金額帶差額、分類預設沖銷、時間在對帳之前', (tester) async {
    final (repo, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => reconFlow(c, ref, acc), store: store);
    await go(tester);
    await tester.enterText(find.byType(TextField).last, '4500');
    await tester.pump();
    await tapFilled(tester, '確認對帳');
    await tapText(tester, '補記一筆');
    // 金額帶好 200、分類預設沖銷。
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '200',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '🩹 沖銷'))
          .selected,
      isTrue,
    );
    await tester.enterText(fieldIn('商家／名稱'), '忘記的飲料');
    await tester.pump();
    await tapFilled(tester, '新增');
    final b = await book(tester, repo);
    final t = b.txs.firstWhere((x) => x.merchant == '忘記的飲料');
    expect(t.category, ledgerWriteOffCat);
    expect(t.amount, 200);
    final cp = b.checkpointsOf(acc.id).last;
    expect(t.occurredAt.isBefore(cp.at), isTrue);
    expect(b.stateOf(b.account(acc.id)!)!.miss, 0);
  });

  testWidgets('一次對帳：兩個帳戶依序填，第一個填完自動跳下一個', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await repo.addAccount(name: 'A戶頭', type: LedgerAccountType.bank);
    await repo.addAccount(name: 'B皮包', type: LedgerAccountType.cash);
    await host(tester, (c, ref) => reconAllFlow(c, ref), store: store);
    await go(tester);
    // 帳戶順序：預設帳戶之後才是自己加的；一路填到 A、B 都有餘額為止。
    for (var i = 0; i < 8; i++) {
      final title = find.textContaining('填餘額：');
      if (title.evaluate().isEmpty) break;
      expect(find.textContaining('一次對帳'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '${100 * (i + 1)}');
      await tester.pump();
      await tapFilled(tester, '記下來');
    }
    final b = await book(tester, repo);
    for (final n in ['A戶頭', 'B皮包']) {
      final a = b.accounts.firstWhere((x) => x.name == n);
      expect(b.stateOf(a), isNotNull, reason: n);
    }
  });

  testWidgets('信用卡對帳：填可刷額，額度沿用；可刷額比算的少會提醒可能有刷卡沒記', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final card = await repo.addAccount(
      name: '玉山卡',
      type: LedgerAccountType.creditCard,
      opening: 50000,
      creditLimit: 50000,
      openingAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    await repo.addTransaction(
      LedgerTx(
        id: 'c1',
        type: LedgerTxType.expense,
        occurredAt: DateTime.now().subtract(const Duration(days: 1)),
        amount: 1000,
        accountId: card.id,
        category: '餐飲',
        merchant: '燒肉',
      ),
    );
    await host(tester, (c, ref) => reconFlow(c, ref, card), store: store);
    await go(tester);
    expect(find.text('現在可刷額（可用額度）'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '48500');
    await tester.pump();
    expect(find.textContaining('可能有刷卡沒記'), findsOneWidget);
    await tapFilled(tester, '確認對帳');
    expect(find.textContaining('先放著（可能是預授權）'), findsOneWidget);
    await tapText(tester, '先放著（可能是預授權）');
    final b = await book(tester, repo);
    expect(b.stateOf(b.account(card.id)!)!.miss, 500);
  });

  // ── 帳戶明細 ──

  testWidgets('帳戶明細：改名字', (tester) async {
    final (repo, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => accountFlow(c, ref, acc), store: store);
    await go(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '改名稱'));
    await settle(tester);
    expect(find.text('編輯帳戶'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '郵局活儲');
    await tester.pump();
    await tapFilled(tester, '儲存');
    expect((await book(tester, repo)).account(acc.id)!.name, '郵局活儲');
  });

  testWidgets('帳戶明細：刪除帳戶（先問、確認才刪）', (tester) async {
    final (repo, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => accountFlow(c, ref, acc), store: store);
    await go(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '刪除帳戶'));
    await settle(tester);
    expect(find.text('刪除帳戶「郵局」？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '刪除').last);
    await settle(tester);
    expect((await book(tester, repo)).account(acc.id), isNull);
    expect(find.textContaining('已刪除帳戶：郵局'), findsOneWidget);
  });

  testWidgets('帳戶明細：刪除帳戶按取消＝不刪', (tester) async {
    final (repo, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => accountFlow(c, ref, acc), store: store);
    await go(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '刪除帳戶'));
    await settle(tester);
    await tester.tap(find.text('取消').last);
    await settle(tester);
    expect((await book(tester, repo)).account(acc.id), isNotNull);
  });

  testWidgets('帳戶明細：現在對帳 → 對帳表單', (tester) async {
    final (_, store, acc) = await withSpend(tester);
    await host(tester, (c, ref) => accountFlow(c, ref, acc), store: store);
    await go(tester);
    await tapFilled(tester, '⚖️ 現在對帳');
    expect(find.text('對帳：郵局'), findsOneWidget);
  });

  // ── 預算 ──

  testWidgets('預算：填總預算跟分類 → 存起來', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final now = DateTime.now();
    await host(
      tester,
      (c, ref) => budgetFlow(c, ref, now.year, now.month),
      store: store,
    );
    await go(tester);
    expect(find.text('${now.month} 月預算'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '30000');
    await tester.pump();
    await tapFilled(tester, '儲存預算');
    final b = await book(tester, repo);
    expect(b.budgetOf(now.year, now.month).total, 30000);
    expect(find.textContaining('月預算已更新'), findsOneWidget);
  });

  // ── 匯入 ──

  testWidgets('匯入：貼兩行 → 匯入 2 筆；空的不能按（邊界）', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await repo.loadBook(); // 預設帳戶
    await host(tester, (c, ref) => importFlow(c, ref), store: store);
    await go(tester);
    expect(find.text('貼上文字匯入'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '沒有可以匯入的'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      '現金｜2026/11/01 08:00｜餐飲｜早餐店｜80\n'
      '現金｜2026/11/01 12:00｜餐飲｜便當｜100',
    );
    await tester.pump();
    await tapFilled(tester, '匯入 2 筆');
    final b = await book(tester, repo);
    expect(b.txs.where((t) => t.source == 'paste').length, 2);
    expect(find.textContaining('匯入 2 筆'), findsOneWidget);
  });

  // ── 清單 ──

  testWidgets('🚩 清單：沒有就寫沒有；有就列出、點了開明細', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await host(tester, (c, ref) => flagsFlow(c, ref), store: store);
    await go(tester);
    expect(find.text('沒有標記的紀錄'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    final acc = (await book(tester, repo)).accounts.first;
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: 'f1',
          type: LedgerTxType.expense,
          occurredAt: DateTime.now(),
          amount: 99,
          accountId: acc.id,
          category: '餐飲',
          merchant: '要查的那筆',
          flagged: true,
        ),
      ),
    );
    await go(tester);
    await tester.tap(find.textContaining('要查的那筆').last);
    await settle(tester);
    expect(find.text('支出明細'), findsOneWidget);
  });

  testWidgets('幫誰付過：沒有就寫沒有', (tester) async {
    await host(tester, (c, ref) => paidForFlow(c, ref));
    await go(tester);
    expect(find.text('還沒有幫別人付過的紀錄'), findsOneWidget);
  });

  testWidgets('分類明細：列這個月這個分類的、按「調整預算」開預算', (tester) async {
    final (_, store, _) = await withSpend(tester);
    final now = DateTime.now();
    await host(
      tester,
      (c, ref) => categoryFlow(c, ref, '餐飲', now.year, now.month),
      store: store,
    );
    await go(tester);
    expect(find.textContaining('餐飲・${now.month} 月'), findsOneWidget);
    await tester.tap(find.text('調整預算'));
    await settle(tester);
    expect(find.text('${now.month} 月預算'), findsOneWidget);
  });

  // ── 交易明細的每個動作 ──

  Future<(LedgerRepository, _MemoryStore)> withTx(
    WidgetTester tester,
    LedgerTx Function(String accountId) make,
  ) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final acc = await repo.addAccount(
      name: '郵局',
      type: LedgerAccountType.bank,
      opening: 5000,
      openingAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    await repo.addTransaction(make(acc.id));
    return (repo, store);
  }

  LedgerTx expense(String acc, {PaidFor? pf}) => LedgerTx(
    id: 't1',
    type: LedgerTxType.expense,
    occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
    amount: 600,
    accountId: acc,
    category: '餐飲',
    merchant: '火鍋',
    paidFor: pf,
  );

  testWidgets('明細：🚩 標記 → 再按取消標記', (tester) async {
    final (repo, store) = await withTx(tester, expense);
    await host(tester, (c, ref) => txDetailFlow(c, ref, 't1'), store: store);
    await go(tester);
    await tester.tap(find.text('🚩 標記'));
    await settle(tester);
    expect((await book(tester, repo)).tx('t1')!.flagged, isTrue);
    expect(find.textContaining('已標記旗幟'), findsOneWidget);
    await go(tester);
    await tester.tap(find.text('取消🚩'));
    await settle(tester);
    expect((await book(tester, repo)).tx('t1')!.flagged, isFalse);
  });

  testWidgets('明細：刪除要確認；取消不刪、確認才刪', (tester) async {
    final (repo, store) = await withTx(tester, expense);
    await host(tester, (c, ref) => txDetailFlow(c, ref, 't1'), store: store);
    await go(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    await tester.tap(find.text('取消').last);
    await settle(tester);
    expect((await book(tester, repo)).tx('t1'), isNotNull);
    await go(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除').last);
    await settle(tester);
    expect((await book(tester, repo)).tx('t1'), isNull);
  });

  testWidgets('明細：退款 → 開退款表單、連到這筆', (tester) async {
    final (repo, store) = await withTx(tester, expense);
    await host(tester, (c, ref) => txDetailFlow(c, ref, 't1'), store: store);
    await go(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '退款'));
    await settle(tester);
    expect(find.text('退哪一筆'), findsOneWidget);
    await tapFilled(tester, '新增');
    final r = (await book(
      tester,
      repo,
    )).txs.firstWhere((t) => t.type == LedgerTxType.refund);
    expect(r.linkedId, 't1');
    expect(r.amount, 600);
  });

  testWidgets('明細：他給了 → 標記就好／轉進戶頭（記一筆還錢、不算收入）', (tester) async {
    final (repo, store) = await withTx(
      tester,
      (a) => expense(a, pf: const PaidFor(amount: 300, people: '小美')),
    );
    await host(tester, (c, ref) => txDetailFlow(c, ref, 't1'), store: store);
    await go(tester);
    await tapFilled(tester, '他給了 ✓');
    expect(find.text('小美 給了 \$300'), findsOneWidget);
    await tester.tap(find.text('轉進 郵局'));
    await settle(tester);
    final b = await book(tester, repo);
    expect(b.tx('t1')!.paidFor!.settled, isTrue);
    final rep = b.txs.firstWhere((t) => t.type == LedgerTxType.repayment);
    expect(rep.amount, 300);
    expect(rep.linkedId, 't1');
    expect(b.statsWhere((_) => true).income, 0, reason: '還錢不算收入');
    expect(find.textContaining('記進 郵局'), findsOneWidget);
    // 改回還沒給。
    await go(tester);
    await tester.ensureVisible(find.text('改回還沒給'));
    await tester.tap(find.text('改回還沒給'));
    await settle(tester);
    expect((await book(tester, repo)).tx('t1')!.paidFor!.settled, isFalse);
  });

  testWidgets('明細：他給了 → 只標記，不記錢進哪', (tester) async {
    final (repo, store) = await withTx(
      tester,
      (a) => expense(a, pf: const PaidFor(amount: 300, people: '小美')),
    );
    await host(tester, (c, ref) => txDetailFlow(c, ref, 't1'), store: store);
    await go(tester);
    await tapFilled(tester, '他給了 ✓');
    await tester.tap(find.text('標記他給了就好'));
    await settle(tester);
    final b = await book(tester, repo);
    expect(b.tx('t1')!.paidFor!.settled, isTrue);
    expect(b.txs.where((t) => t.type == LedgerTxType.repayment), isEmpty);
  });

  testWidgets('明細：找不到那筆（已刪）就什麼都不開（邊界）', (tester) async {
    await host(tester, (c, ref) => txDetailFlow(c, ref, 'nope'));
    await go(tester);
    expect(find.textContaining('明細'), findsNothing);
    expect(tester.takeException(), isNull);
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

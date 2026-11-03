import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';
import 'package:lume/features/ledger/ledger_ui.dart';

/// 記帳四個分頁在手機寬度（360）畫得出來、不爆版，有資料跟沒資料都要；
/// 記一筆、對帳、貼上匯入、帳戶明細這些抽屜也要打得開。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_MemoryStore> seeded() async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final bank = await repo.addAccount(
      name: '中信活存 名字很長很長很長很長很長很長',
      type: LedgerAccountType.bank,
      opening: 45000,
      openingAt: start,
    );
    final card = await repo.addAccount(
      name: '中信信用卡',
      type: LedgerAccountType.creditCard,
      opening: 87600,
      openingAt: start,
      creditLimit: 100000,
    );
    await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 2000,
      openingAt: start,
    );
    final lunch = LedgerTx(
      id: ledgerId(),
      type: LedgerTxType.expense,
      occurredAt: start.add(const Duration(hours: 12)),
      amount: 2400,
      accountId: card.id,
      category: '餐飲',
      merchant: '鼎泰豐 聚餐 名字很長很長很長很長很長很長很長很長',
      note: '備註也很長很長很長很長很長很長',
      flagged: true,
      paidFor: const PaidFor(amount: 1200, people: '阿明、小華'),
    );
    await repo.addTransactions([
      lunch,
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.transfer,
        occurredAt: start.add(const Duration(hours: 13)),
        amount: 3000,
        accountId: bank.id,
        toAccountId: (await repo.loadBook()).accounts.last.id,
        merchant: 'ATM提款',
      ),
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.repayment,
        occurredAt: start.add(const Duration(hours: 14)),
        amount: 600,
        accountId: bank.id,
        linkedId: lunch.id,
      ),
    ]);
    await repo.addCheckpoint(
      LedgerCheckpoint(
        id: ledgerId(),
        accountId: bank.id,
        at: start.add(const Duration(hours: 20)),
        balance: 45000 - 3000 + 600 - 630,
      ),
    );
    await repo.setBudgets(
      '${now.year}-${now.month.toString().padLeft(2, '0')}',
      1000,
      {'餐飲': 500},
    );
    return store;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page,
    _MemoryStore store,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(home: page),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> show(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
    f,
    150,
    scrollable: find.byType(Scrollable).first,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  for (final empty in [false, true]) {
    final tag = empty ? '（沒資料）' : '（有資料）';
    for (final tab in LedgerTab.values) {
      testWidgets('${tab.title}分頁畫得出來$tag', (tester) async {
        final store = empty ? _MemoryStore() : await seeded();
        await pump(tester, LedgerPage(tab: tab), store);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('首頁看得到兩件事分開：控制開銷、記帳完整度（活存差 \$630）', (tester) async {
    await pump(tester, const LedgerPage(tab: LedgerTab.home), await seeded());
    expect(find.textContaining('控制開銷'), findsOneWidget);
    expect(find.textContaining('記帳完整度'), findsOneWidget);
    // 首頁顯示當月已記錄幾筆（seeded 本月有 3 筆）；繳卡費要用「轉帳」記的說明也寫清楚。
    expect(find.textContaining('已記錄 3 筆'), findsOneWidget);
    expect(find.textContaining('請用「轉帳」記'), findsOneWidget);
    expect(find.text('⚠ 差 \$630'), findsOneWidget);
    // 本月消費只算自己的 1,200（幫付 1,200 不算、提款不算）。
    expect(find.text('\$1,200'), findsWidgets);
  });

  testWidgets('記一筆、交易明細、帳戶明細、對帳、匯入、別人還欠你都打得開', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('記一筆'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    await tester.tap(find.text('⚠ 差 \$630'));
    await settle(tester);
    expect(find.text('補記一筆'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('⚖️ 現在對帳'));
    await settle(tester);
    expect(find.textContaining('對帳：'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    await show(tester, find.textContaining('別人還欠你').first);
    await tester.tap(find.textContaining('別人還欠你').first);
    await settle(tester);
    expect(find.text('他給了 ✓'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    // 看紀錄走底部的「明細」分頁（首頁不重複放列表）：換到明細再點那一筆。
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    await tester.tap(find.textContaining('鼎泰豐').first);
    await settle(tester);
    expect(find.text('支出明細'), findsOneWidget);
    expect(find.textContaining('跟 阿明、小華 一起'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('帳戶分頁：貼上匯入、預算抽屜都打得開', (tester) async {
    await pump(
      tester,
      const LedgerPage(tab: LedgerTab.accounts),
      await seeded(),
    );
    for (final title in ['貼上文字匯入', '預算']) {
      await tester.scrollUntilVisible(find.text(title), 200);
      await tester.tap(find.text(title));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: title);
      await tester.tap(find.byTooltip('關閉'));
      await settle(tester);
    }
  });

  testWidgets('完全沒資料也能直接記：自動有預設三個帳戶、不跳開始記帳、餘額都不用填', (tester) async {
    final store = _MemoryStore();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    expect(find.text('開始記帳'), findsNothing);
    // 記帳完整度：還沒對過的帳戶不寫「還沒對帳」之類的狀態，只有一顆「對帳」按鈕。
    expect(find.text('對帳'), findsNWidgets(3));
    expect(find.text('沒填餘額'), findsNothing);
    expect(find.text('還沒對帳'), findsNothing);
    expect(find.text('全部對上'), findsNothing);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    expect(book!.accounts.map((a) => a.name), ['中信活存', '中信卡', '現金']);
    expect(book.checkpoints, isEmpty);
    // 記一筆，不填任何餘額。
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '120');
    await tester.pump();
    // 商家名稱必填：沒填按鈕按不了。
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '記下來'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).at(2), '早餐');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '記下來'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final after = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    expect(after!.txs.single.amount, 120);
  });

  testWidgets('記一筆時填「這筆之後的餘額」→ 附在這筆上；下一筆餘額對不上就掛漏記標籤', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    final bank = book0!.accounts.first;
    await tester.runAsync(() async {
      final t1 = LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 11, 2, 10),
        amount: 100,
        accountId: bank.id,
        category: '餐飲',
        merchant: '早餐',
      );
      await repo.addTransaction(t1);
      await repo.setTxCheckpoint(
        txId: t1.id,
        accountId: bank.id,
        at: t1.occurredAt,
        value: 1000,
        creditLimit: null,
      );
      // 下一筆花 100，餘額卻少了 600：中間漏記 500。
      final t2 = LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.expense,
        occurredAt: DateTime(2026, 11, 3, 10),
        amount: 100,
        accountId: bank.id,
        category: '餐飲',
        merchant: '午餐',
      );
      await repo.addTransaction(t2);
      await repo.setTxCheckpoint(
        txId: t2.id,
        accountId: bank.id,
        at: t2.occurredAt,
        value: 400,
        creditLimit: null,
      );
    });
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.text('⚠ 漏記 \$500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('轉帳打開「轉給別人（算支出）」→ 存成一筆支出', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.text('轉帳'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '800');
    await tester.pump();
    await tester.tap(find.text('轉給別人（算支出）'));
    await tester.pump();
    expect(find.text('買什麼（分類）'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), '小美代買');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '記下來'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    final t = book!.txs.firstWhere((t) => t.amount == 800);
    expect(t.type, LedgerTxType.expense);
    expect(t.toAccountId, isNull);
    expect(ledgerExpenseCats.containsKey(t.category), isTrue);
  });

  testWidgets('沒填餘額的帳戶在帳戶分頁可以「填餘額」', (tester) async {
    final store = _MemoryStore();
    await tester.runAsync(
      () => LedgerRepository(
        store,
      ).addAccount(name: '郵局', type: LedgerAccountType.bank),
    );
    await pump(tester, const LedgerPage(tab: LedgerTab.accounts), store);
    expect(find.textContaining('沒填餘額'), findsOneWidget);
    await tester.tap(find.text('填餘額'));
    await settle(tester);
    expect(find.text('填餘額：郵局'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '12000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '記下來'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    expect(book!.stateOf(book.accounts.single)!.now, 12000);
  });

  testWidgets('每個分頁右上角都有「貼上文字匯入」，點了打得開', (tester) async {
    for (final tab in LedgerTab.values) {
      await pump(tester, LedgerPage(tab: tab), await seeded());
      expect(find.byTooltip('貼上文字匯入'), findsOneWidget, reason: tab.title);
    }
    await tester.tap(find.byTooltip('貼上文字匯入'));
    await settle(tester);
    expect(find.text('貼上文字匯入'), findsWidgets);
    expect(find.textContaining('帳戶｜日期時間｜分類｜商家｜金額'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('記一筆上方貼一行文字 → 下面自動填好，記下來就存進去', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(
      find.byType(TextField).first,
      '現金｜2026/11/05 15:00｜寵物｜飼料｜650｜｜｜｜｜補貨',
    );
    await tester.pump();
    expect(find.textContaining('讀懂了'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '記下來'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    final t = book!.txs.firstWhere((t) => t.amount == 650);
    expect(t.category, '寵物');
    expect(t.merchant, '飼料');
    expect(t.note, '補貨');
    expect(t.occurredAt, DateTime(2026, 11, 5, 15));
    expect(book.accountName(t.accountId), '現金');
  });

  testWidgets('明細頂部搜尋：輸入後每個欄位都搜（不管月份），清除就回來', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    // 備註、商家、金額都搜得到：seeded 有一筆商家含「鼎泰豐」。
    await tester.enterText(find.byType(TextField).first, '鼎泰豐');
    await tester.pump();
    expect(find.textContaining('搜尋「鼎泰豐」'), findsOneWidget);
    expect(find.textContaining('1 筆'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '完全找不到的字');
    await tester.pump();
    expect(find.text('沒有符合的紀錄'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜尋'));
    await tester.pump();
    expect(find.textContaining('搜尋「'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('明細可以篩分類：只列出有出現的分類，點了只剩那個分類', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    // seeded 只有「餐飲」那一筆支出（鼎泰豐）。
    expect(find.text('🍜 餐飲'), findsOneWidget);
    expect(find.text('🐾 寵物'), findsNothing);
    await tester.tap(find.text('🍜 餐飲'));
    await tester.pump();
    expect(find.textContaining('鼎泰豐'), findsWidgets);
    expect(find.textContaining('篩選中'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await tester.pump();
    expect(find.textContaining('篩選中'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2026 年 11 月以前的月份：首頁卡片跟明細上方標註資料不準確', (tester) async {
    expect(isBeforeAccurate(2026, 10), isTrue);
    expect(isBeforeAccurate(2026, 11), isFalse);
    expect(isBeforeAccurate(2027, 1), isFalse);
    final store = await seeded();
    for (final tab in [LedgerTab.home, LedgerTab.list]) {
      await pump(tester, LedgerPage(tab: tab), store);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LedgerPage)),
      );
      // 切到 2026/10：有提示；切到 2026/11：沒有。
      container.read(ledgerMonthProvider.notifier).state = DateTime(2026, 10);
      await tester.pump();
      expect(find.textContaining('資料不準確'), findsOneWidget, reason: tab.title);
      container.read(ledgerMonthProvider.notifier).state = DateTime(2026, 11);
      await tester.pump();
      expect(find.textContaining('資料不準確'), findsNothing, reason: tab.title);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('記一筆跟別人一起：當下就能勾「對方已經給我了」，存下來就是已給', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1000');
    await tester.enterText(find.byType(TextField).at(2), '聚餐');
    await tester.pump();
    final pf = find.text('👥 跟別人一起（對方要給我錢）');
    await tester.scrollUntilVisible(
      pf,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(pf);
    await tester.pump();
    final done = find.text('✓ 對方已經給我了');
    await tester.scrollUntilVisible(
      done,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(done);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '記下來'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    final t = book!.txs.firstWhere((t) => t.merchant == '聚餐');
    expect(t.paidFor!.settled, isTrue);
    expect(t.ownSpend, 500, reason: '預設對方要給一半');
    expect(book.owes.where((o) => o.tx.id == t.id), isEmpty);
  });

  testWidgets('拆分：一定要拆滿整筆才能存，存下來統計照拆分算', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1000');
    await tester.enterText(find.byType(TextField).at(2), '家樂福');
    await tester.pump();
    final split = find.text('拆分（一筆裡有不同分類）');
    await tester.scrollUntilVisible(
      split,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(split);
    await tester.pump();
    expect(find.textContaining('拆分（加起來要剛好等於整筆）'), findsOneWidget);
    // 第一份自動帶整筆 1000，第二份空 → 不能存。
    expect(find.textContaining('每一份都要填金額'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '記下來'))
          .onPressed,
      isNull,
    );
    // TextField 順序：貼上(0)、整筆金額(1)、拆分第一份(2)、第二份(3)，商家在分類之後。
    await tester.enterText(find.byType(TextField).at(2), '500');
    await tester.enterText(find.byType(TextField).at(3), '500');
    await tester.pump();
    expect(find.textContaining('剛好拆滿'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '記下來'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    final t = book!.txs.firstWhere((t) => t.merchant == '家樂福');
    expect(t.isSplit, isTrue);
    expect(t.splits.map((s) => s.amount), [500, 500]);
    expect(t.splits.map((s) => s.category), containsAll(['生活']));
    final now = DateTime.now();
    final st = book.statsWhere((x) => x.id == t.id);
    expect(st.spend, 1000);
    expect(st.byCategory.values.fold(0, (a, c) => a + c), 1000);
    expect(now.year, greaterThan(2000));
  });

  testWidgets('明細「全部時間」：不管月份，選分類就看那個分類總共花多少', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    final card = book0!.accounts.firstWhere((a) => a.isCard);
    await tester.runAsync(() async {
      for (final (m, amt) in [(9, 300), (10, 500), (11, 200)]) {
        await repo.addTransaction(
          LedgerTx(
            id: ledgerId(),
            type: LedgerTxType.expense,
            occurredAt: DateTime(2026, m, 5, 12),
            amount: amt,
            accountId: card.id,
            category: '菸酒',
            merchant: '菸酒$m月',
          ),
        );
      }
    });
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LedgerPage)),
    );
    container.read(ledgerMonthProvider.notifier).state = DateTime(2026, 11);
    await tester.pump();
    expect(find.textContaining('1 筆'), findsOneWidget); // 只有 11 月那筆
    // 「查看時間」按鈕 → 選單 → 全部時間。
    expect(find.textContaining('查看時間：'), findsOneWidget);
    await tester.tap(find.textContaining('查看時間：'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有紀錄的月份'), findsOneWidget);
    await tester.tap(find.textContaining('全部時間（'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🍺 菸酒'));
    await tester.pump();
    // 三個月加起來 300+500+200 = 1000。
    expect(find.textContaining('3 筆・菸酒 \$1,000'), findsOneWidget);
    expect(find.textContaining('全部時間）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('明細每一條的圖示看付款方式：現金＝鈔票、刷卡＝信用卡，轉帳照原本的符號', (tester) async {
    final store = await seeded();
    final repo = LedgerRepository(store);
    final b = await tester.runAsync(() => repo.loadBook());
    final cash = b!.accounts.firstWhere(
      (a) => a.type == LedgerAccountType.cash,
    );
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: DateTime.now(),
          amount: 120,
          accountId: cash.id,
          category: '餐飲',
          merchant: '便當',
        ),
      ),
    );
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.text('💵'), findsOneWidget, reason: '現金那筆');
    expect(find.text('💳'), findsOneWidget, reason: '刷卡那筆（鼎泰豐）');
    expect(find.text('⇄'), findsOneWidget, reason: '轉帳照原本的符號');
    expect(tester.takeException(), isNull);
  });

  testWidgets('跟別人一起：按「他給了 ✓」→ 標記就好，就不再列在別人還欠你', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await show(tester, find.textContaining('別人還欠你').first);
    await tester.tap(find.textContaining('別人還欠你').first);
    await settle(tester);
    expect(find.text('阿明、小華 要給 \$600'), findsOneWidget);
    await tester.tap(find.text('他給了 ✓').first);
    await settle(tester);
    await tester.tap(find.text('標記他給了就好'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    expect(book!.owes, isEmpty);
    // 只是標記：沒有多記一筆還錢。
    expect(
      book.txs.where((t) => t.type == LedgerTxType.repayment),
      hasLength(1),
    );
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

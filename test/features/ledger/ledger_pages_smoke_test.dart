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

  /// 明細篩選是一顆毛玻璃下拉：點開「篩選：」再選一項。
  Future<void> pickFilter(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining('篩選：'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

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

    // 「別人還欠你」的概念、功能、首頁卡片都拿掉了（使用者）。
    expect(find.textContaining('別人還欠你'), findsNothing);
    expect(tester.takeException(), isNull);

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
    expect(find.text('對帳'), findsNWidgets(4));
    expect(find.text('沒填餘額'), findsNothing);
    expect(find.text('還沒對帳'), findsNothing);
    expect(find.text('全部對上'), findsNothing);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    expect(book!.accounts.map((a) => a.name), ['中信活存', '中信卡', '台新卡', '現金']);
    expect(book.checkpoints, isEmpty);
    // 記一筆，不填任何餘額。
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(2), '120');
    await tester.pump();
    // 商家名稱必填：沒填按鈕按不了。
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).at(1), '早餐');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
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

  testWidgets('繳卡費兩邊餘額都填：戶頭或卡任何一邊對不上，這一條都掛漏記', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    final bank = book0!.accounts.firstWhere(
      (a) => a.type == LedgerAccountType.bank,
    );
    final card = book0.accounts.firstWhere((a) => a.isCard);
    await tester.runAsync(() async {
      Future<LedgerTx> add(
        LedgerTxType type,
        int day,
        int amount,
        String acc,
        String m, {
        String? to,
      }) async {
        final t = LedgerTx(
          id: ledgerId(),
          type: type,
          occurredAt: DateTime(2026, 11, day, 10),
          amount: amount,
          accountId: acc,
          toAccountId: to,
          category: type == LedgerTxType.expense ? '餐飲' : null,
          merchant: m,
        );
        await repo.addTransaction(t);
        return t;
      }

      Future<void> cp(LedgerTx t, String acc, bool isCard, int v) =>
          repo.setTxCheckpoint(
            txId: t.id,
            accountId: acc,
            at: t.occurredAt,
            value: v,
            creditLimit: null,
            isCard: isCard,
          );
      // 起點：戶頭剩 1000、卡可刷 9000。
      await cp(
        await add(LedgerTxType.expense, 1, 10, bank.id, '起點戶頭'),
        bank.id,
        false,
        1000,
      );
      await cp(
        await add(LedgerTxType.expense, 1, 10, card.id, '起點卡'),
        card.id,
        true,
        9000,
      );
      // 繳卡費 300：戶頭該剩 700、可刷該變 9300。戶頭填 600（少 100）、卡填對。
      final pay1 = await add(
        LedgerTxType.transfer,
        2,
        300,
        bank.id,
        '繳卡費',
        to: card.id,
      );
      await cp(pay1, bank.id, false, 600);
      await cp(pay1, card.id, true, 9300);
      // 再繳 200：戶頭填對（400）、卡的可刷額填 9400（該是 9500，卡那邊差 100）。
      final pay2 = await add(
        LedgerTxType.transfer,
        3,
        200,
        bank.id,
        '繳卡費',
        to: card.id,
      );
      await cp(pay2, bank.id, false, 400);
      await cp(pay2, card.id, true, 9400);
    });
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.textContaining('漏記'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('從畫面記繳卡費、兩邊餘額都填（戶頭差 100）→ 存下來這一條掛漏記', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    final bank = book0!.accounts.firstWhere(
      (a) => a.type == LedgerAccountType.bank,
    );
    final card = book0.accounts.firstWhere((a) => a.isCard);
    await tester.runAsync(() async {
      Future<void> start(String acc, bool isCard, int v, String m) async {
        final t = LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: DateTime(2026, 11, 1, 10),
          amount: 10,
          accountId: acc,
          category: '餐飲',
          merchant: m,
        );
        await repo.addTransaction(t);
        await repo.setTxCheckpoint(
          txId: t.id,
          accountId: acc,
          at: t.occurredAt,
          value: v,
          creditLimit: null,
          isCard: isCard,
        );
      }

      await start(bank.id, false, 1000, '起點戶頭');
      await start(card.id, true, 9000, '起點卡');
    });
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.text('轉帳'));
    await tester.pump();
    await tester.ensureVisible(find.text('繳卡費'));
    await tester.pump();
    await tester.tap(find.text('繳卡費'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), '300');
    await tester.pump();
    // 兩個餘額欄位：戶頭（該剩 700，填 600）、卡（可刷額該是 9300，填對）。
    await tester.enterText(find.byType(TextField).at(3), '600');
    await tester.enterText(find.byType(TextField).at(4), '9300');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('⚠ 中信活存漏記 \$100'), findsOneWidget);
  });

  testWidgets('右上角有雲端同步按鈕，點了跳出多裝置同步的懸浮視窗', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.tap(find.byTooltip('多裝置同步'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('多裝置同步'), findsOneWidget);
    await tester.tap(find.byTooltip('關閉'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('設定可以選不顯示備註：關掉後明細每一條不再顯示備註', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: DateTime.now(),
          amount: 90,
          accountId: book0!.accounts.first.id,
          category: '餐飲',
          merchant: '早餐店',
          note: '蛋餅加豆漿',
        ),
      ),
    );
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.textContaining('蛋餅加豆漿'), findsOneWidget);
    ProviderScope.containerOf(
      tester.element(find.byType(LedgerPage)),
    ).read(ledgerShowNoteProvider.notifier).state = false;
    await tester.pump();
    expect(find.textContaining('蛋餅加豆漿'), findsNothing);
    expect(find.textContaining('早餐店'), findsOneWidget);
  });

  testWidgets('明細：查看時間跟篩選放同一行，一個左一個右', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    final range = tester.getCenter(find.textContaining('查看時間'));
    final filter = tester.getCenter(find.textContaining('篩選：'));
    expect((range.dy - filter.dy).abs() < 4, isTrue);
    expect(range.dx < filter.dx, isTrue);
  });

  testWidgets('首頁本月花費底下有「平均每天花多少」小字', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    expect(find.textContaining('平均每天花'), findsOneWidget);
    expect(find.textContaining('到今天共'), findsOneWidget);
  });

  testWidgets('首頁「幫誰付過」卡片：跟標記旗幟一樣，點開列出幫別人付的紀錄', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    expect(find.text('👥 幫誰付過'), findsOneWidget);
    expect(find.text('🚩 標記旗幟'), findsOneWidget);
    await tester.ensureVisible(find.text('👥 幫誰付過'));
    await tester.pump();
    await tester.tap(find.text('👥 幫誰付過'));
    await settle(tester);
    expect(find.textContaining('鼎泰豐'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跟別人一起：欄位叫「幫誰」，底下直接列最近幫過的人，點了就填進去', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    final pf = find.text('👥 跟別人一起（對方要給我錢）');
    await tester.scrollUntilVisible(
      pf,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(pf);
    await tester.pump();
    expect(find.text('幫誰'), findsOneWidget);
    expect(find.text('跟誰'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '阿明、小華'));
    await tester.pump();
    // 一打開，幫誰就預設填快選列的第一個，不是寫「朋友」。
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '阿明、小華'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '阿明、小華'));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '阿明、小華'))
          .selected,
      isTrue,
    );
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
    await tester.enterText(find.byType(TextField).at(2), '800');
    await tester.pump();
    await tester.tap(find.text('轉給別人（算支出）'));
    await tester.pump();
    expect(find.text('買什麼（分類）'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '小美代買');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
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
    expect(find.textContaining('沒填餘額'), findsNWidgets(2));
    await tester.tap(find.text('填餘額').first);
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
    expect(
      book!.stateOf(book.accounts.firstWhere((a) => a.name == '郵局'))!.now,
      12000,
    );
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
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
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

  testWidgets('明細搜尋框：打一個字之後還在輸入（月份列消失不能害搜尋框被重建、掉焦點）', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    bool focused() => tester
        .widget<EditableText>(find.byType(EditableText).first)
        .focusNode
        .hasFocus;
    expect(focused(), isTrue);
    await tester.enterText(find.byType(TextField).first, '鼎');
    await tester.pump();
    expect(find.textContaining('搜尋「鼎」'), findsOneWidget);
    expect(focused(), isTrue, reason: '打第一個字後搜尋框不能失去焦點');
    await tester.enterText(find.byType(TextField).first, '鼎泰');
    await tester.pump();
    expect(focused(), isTrue);
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
    // 一顆下拉按鈕，點開才看得到分類；沒有出現的分類（寵物）不列。
    expect(find.textContaining('篩選：全部'), findsOneWidget);
    await tester.tap(find.textContaining('篩選：'));
    await tester.pumpAndSettle();
    expect(find.text('🍜 餐飲'), findsOneWidget);
    expect(find.text('🐾 寵物'), findsNothing);
    await tester.tap(find.text('🍜 餐飲'));
    await tester.pumpAndSettle();
    expect(find.textContaining('鼎泰豐'), findsWidgets);
    expect(find.textContaining('篩選中'), findsOneWidget);
    expect(find.textContaining('篩選：餐飲'), findsOneWidget);
    await pickFilter(tester, '全部');
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

  testWidgets('記一筆跟別人一起：當下就能勾「對方已給」，存下來就是已給', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(2), '1000');
    await tester.enterText(find.byType(TextField).at(1), '聚餐');
    await tester.pump();
    final pf = find.text('👥 跟別人一起（對方要給我錢）');
    await tester.scrollUntilVisible(
      pf,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(pf);
    await tester.pump();
    final done = find.text('✓ 對方已給');
    await tester.scrollUntilVisible(
      done,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(done);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
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
    await tester.enterText(find.byType(TextField).at(2), '1000');
    await tester.enterText(find.byType(TextField).at(1), '家樂福');
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
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    // TextField 順序：貼上(0)、商家(1)、整筆金額(2)、第一份金額(3)、第一份品項名稱(4)、
    // 第二份金額(5)、第二份品項名稱(6)。
    await tester.enterText(find.byType(TextField).at(3), '500');
    await tester.enterText(find.byType(TextField).at(5), '500');
    await tester.pump();
    expect(find.textContaining('剛好拆滿'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
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

  testWidgets('拆分：每一份可寫品項名稱、標幫人付、已給；自己的消費只算沒幫人付的那份', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(2), '1000');
    await tester.enterText(find.byType(TextField).at(1), '全聯');
    await tester.pump();
    final split = find.text('拆分（一筆裡有不同分類）');
    await tester.scrollUntilVisible(
      split,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(split);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(3), '600');
    await tester.enterText(find.byType(TextField).at(4), '麵包');
    await tester.enterText(find.byType(TextField).at(5), '400');
    await tester.enterText(find.byType(TextField).at(6), '幫忙買的飲料');
    await tester.pump();
    // 還沒標幫人付：沒有幫誰欄位。
    expect(find.byKey(const ValueKey('splitPeople1')), findsNothing);
    final chip = find.widgetWithText(FilterChip, '👥 幫人付').last;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    // 標了之後，幫誰就在這一份底下（不是表單最底下）。
    expect(find.byKey(const ValueKey('splitPeople1')), findsOneWidget);
    expect(find.byKey(const ValueKey('splitPeople0')), findsNothing);
    expect(find.widgetWithText(FilterChip, '✓ 已給'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilterChip, '✓ 已給'));
    await tester.tap(find.widgetWithText(FilterChip, '✓ 已給'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('splitPeople1')));
    // 標幫人付時，幫誰預設是快選列的第一個（最近幫過的人），不是「朋友」。
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('splitPeople1')))
          .controller!
          .text,
      '阿明、小華',
    );
    await tester.enterText(find.byKey(const ValueKey('splitPeople1')), 'Cen');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    final t = book!.txs.firstWhere((t) => t.merchant == '全聯');
    expect(t.splits.map((s) => s.name), ['麵包', '幫忙買的飲料']);
    expect(t.splits.map((s) => s.forOther), [false, true]);
    expect(t.splits.map((s) => s.settled), [false, true]);
    expect(t.splits.map((s) => s.people), ['', 'Cen']);
    expect(t.paidFor?.amount, 400);
    expect(t.paidFor?.people, 'Cen');
    expect(t.paidFor?.settled, isTrue);
    expect(t.ownSpend, 600);
    // 統計只算沒幫人付的那份。
    final st = book.statsWhere((x) => x.id == t.id);
    expect(st.spend, 600);
    // 搜得到品項名稱。
    expect(book.matches(t, '飲料'), isTrue);
    // 外面標「改回還沒給」，每一份也一起改回。
    final back = t.withSettled(false);
    expect(back.paidFor!.settled, isFalse);
    expect(back.splits.map((s) => s.settled), [false, false]);
  });

  testWidgets('拆分：兩份可以幫不同的人，整筆的幫誰是兩個人接起來，快選列各份幫過的人', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(2), '1000');
    await tester.enterText(find.byType(TextField).at(1), '聚餐');
    await tester.pump();
    final split = find.text('拆分（一筆裡有不同分類）');
    await tester.scrollUntilVisible(
      split,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(split);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(3), '300');
    await tester.enterText(find.byType(TextField).at(5), '700');
    await tester.pump();
    for (final i in [0, 1]) {
      final chip = find.widgetWithText(FilterChip, '👥 幫人付').at(i);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const ValueKey('splitPeople0')));
    await tester.enterText(find.byKey(const ValueKey('splitPeople0')), 'Cen');
    await tester.ensureVisible(find.byKey(const ValueKey('splitPeople1')));
    await tester.enterText(find.byKey(const ValueKey('splitPeople1')), 'Amy');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    final t = book!.txs.firstWhere((t) => t.merchant == '聚餐');
    expect(t.splits.map((s) => s.people), ['Cen', 'Amy']);
    expect(t.paidFor?.people, 'Cen、Amy');
    expect(t.paidFor?.amount, 1000);
    expect(book.matches(t, 'amy'), isTrue);
  });

  testWidgets('明細搜尋：拆分的 item 把每一份的品項名稱列出來，沒搜尋時不列', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final book0 = await tester.runAsync(() => repo.loadBook());
    final card = book0!.accounts.firstWhere((a) => a.isCard);
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: DateTime.now(),
          amount: 1000,
          accountId: card.id,
          category: '生活',
          merchant: '全聯',
          splits: const [
            LedgerSplit(category: '生活', amount: 600, name: '衛生紙'),
            LedgerSplit(
              category: '餐飲',
              amount: 400,
              name: '幫忙買的飲料',
              forOther: true,
            ),
          ],
          paidFor: const PaidFor(amount: 400, people: 'Cen'),
        ),
      ),
    );
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.textContaining('└'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '飲料');
    await tester.pump();
    // 兩份都列出來，符合的那份有幫人付標記。
    expect(find.textContaining('└ 衛生紙（生活）'), findsOneWidget);
    expect(find.textContaining('└ 幫忙買的飲料（餐飲）'), findsOneWidget);
    expect(find.textContaining('👥幫人付'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await pickFilter(tester, '🍺 菸酒');
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

  testWidgets('拆分的大筆：預設一個大項（已拆）；選分類只顯示那個分類的子項', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final b0 = await tester.runAsync(() => repo.loadBook());
    final cash = b0!.accounts.firstWhere(
      (a) => a.type == LedgerAccountType.cash,
    );
    await tester.runAsync(
      () => repo.addTransaction(
        LedgerTx(
          id: ledgerId(),
          type: LedgerTxType.expense,
          occurredAt: DateTime.now(),
          amount: 1000,
          accountId: cash.id,
          category: '生活',
          merchant: '家樂福',
          splits: const [
            LedgerSplit(category: '生活', amount: 600),
            LedgerSplit(category: '餐飲', amount: 400),
          ],
        ),
      ),
    );
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    // 預設：一個大項，金額是整筆，標「已拆 2 份」。
    expect(find.text('−\$1,000'), findsOneWidget);
    expect(find.text('已拆 2 份'), findsOneWidget);
    // 選分類「餐飲」：只顯示那一份 400，旁邊寫拆分自 1,000。
    await pickFilter(tester, '🍜 餐飲');
    expect(find.text('−\$400'), findsOneWidget);
    expect(find.text('拆分自 \$1,000'), findsOneWidget);
    expect(find.text('−\$1,000'), findsNothing);
    expect(find.textContaining('餐飲 \$400'), findsOneWidget); // 上面統計也是 400
    // 換成「生活」：600。
    await pickFilter(tester, '🍜 餐飲'); // 再點一次＝取消
    await pickFilter(tester, '🏡 生活');
    expect(find.text('−\$600'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('明細：選月份那一行在搜尋框上面；篩選列的旗幟選項叫「注意」', (tester) async {
    await pump(tester, const LedgerPage(tab: LedgerTab.list), await seeded());
    final month = tester.getTopLeft(find.byTooltip('上個月')).dy;
    final search = tester.getTopLeft(find.byIcon(Icons.search_rounded)).dy;
    expect(month, lessThan(search), reason: '月份列在搜尋框上面');
    // 篩選是一顆毛玻璃下拉；旗幟那一項叫「注意」。
    await tester.tap(find.textContaining('篩選：'));
    await tester.pumpAndSettle();
    expect(find.textContaining('注意 '), findsOneWidget);
    expect(find.textContaining('要注意'), findsNothing);
    expect(find.textContaining('旗幟'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一人一半除不盡：對方給少的那份、我多出一塊（101 → 對方 50、我 51）', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '便當');
    await tester.enterText(find.byType(TextField).at(2), '101');
    await tester.pump();
    final pf = find.text('👥 跟別人一起（對方要給我錢）');
    await tester.scrollUntilVisible(
      pf,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(pf);
    await tester.pump();
    expect(find.widgetWithText(ChoiceChip, '一半 \$50'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '一半 \$50'))
          .selected,
      isTrue,
    );
    expect(find.widgetWithText(ChoiceChip, '一半 \$51'), findsNothing);
  });

  testWidgets('跟別人一起：預設一半時「一半」選項是亮的；改成全部或自己打就跟著變', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.pump();
    final pf = find.text('👥 跟別人一起（對方要給我錢）');
    await tester.scrollUntilVisible(
      pf,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(pf);
    await tester.pump();
    bool on(String text) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, text))
        .selected;
    // 預設對方要給一半（50）：「一半」亮、「全部」不亮。
    expect(on('一半 \$50'), isTrue);
    expect(on('全部 \$100'), isFalse);
    await tester.ensureVisible(find.text('全部 \$100'));
    await tester.pump();
    await tester.tap(find.text('全部 \$100'));
    await tester.pump();
    expect(on('一半 \$50'), isFalse);
    expect(on('全部 \$100'), isTrue);
    // 自己打 70：兩個都不亮。
    final pfAmount = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.prefixText == '\$' &&
          w.controller?.text == '100',
    );
    await tester.enterText(pfAmount, '70');
    await tester.pump();
    expect(on('一半 \$50'), isFalse);
    expect(on('全部 \$100'), isFalse);
    // 沒有「還欠你」那種說明了，標題也改叫「對方已給」。
    expect(find.text('✓ 對方已給'), findsOneWidget);
    expect(find.textContaining('不會列在'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跟別人一起：在那筆按「他給了 ✓」→ 只標記，標籤保留並顯示已給', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.textContaining('要給 \$1,200'), findsOneWidget);
    await tester.tap(find.textContaining('鼎泰豐').first);
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('他給了 ✓'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
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
    // 標籤保留「要給 $金額」，後面多 ✓已給。
    await pump(tester, const LedgerPage(tab: LedgerTab.list), store);
    expect(find.textContaining('✓已給'), findsOneWidget);
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

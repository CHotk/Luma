import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/ledger_subscriptions.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';
import 'package:lume/features/ledger/ledger_subs_page.dart';
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

  // 表單裡的 訂閱｜借款、信用卡｜小額借款｜信貸 切換（頁面上也有同名的篩選鈕，要指到表單裡的）。
  Finder kindSeg(String t) => find.descendant(
    of: find.byType(SegmentedButton<LedgerChargeKind>),
    matching: find.text(t),
  );
  Finder typeSeg(String t) => find.descendant(
    of: find.byType(SegmentedButton<LedgerDebtType>),
    matching: find.text(t),
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

  testWidgets('每月扣款：新增、合計只算訂閱中、停用排後面不算合計、刪除；首頁入口寫合計', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerSubsPage(), store);
    expect(find.text('還沒有每月扣款'), findsOneWidget);
    expect(find.text('每月扣款合計・扣款中 0 項'), findsOneWidget);

    Future<void> add(String name, String amount, String day) async {
      await tester.tap(find.byTooltip('新增每月扣款'));
      await settle(tester);
      // TextField 順序：名稱(0)、金額(1)、每月幾號(2)、備註(3)。
      await tester.enterText(find.byType(TextField).at(0), name);
      await tester.enterText(find.byType(TextField).at(1), amount);
      await tester.enterText(find.byType(TextField).at(2), day);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '新增'));
      await settle(tester);
      // 等通知收掉，不然它蓋在右上角的「新增每月扣款」鈕上。
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }

    // 幾號沒填或超過 31 不能存。
    await tester.tap(find.byTooltip('新增每月扣款'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'X');
    await tester.enterText(find.byType(TextField).at(1), '100');
    await tester.enterText(find.byType(TextField).at(2), '32');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    expect(find.text('每月幾號要在 1～31 之間'), findsOneWidget);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    await add('Netflix', '390', '12');
    await add('Spotify', '149', '3');
    expect(tester.takeException(), isNull);
    expect(find.text('每月扣款合計・扣款中 2 項'), findsOneWidget);
    expect(find.text('\$539'), findsOneWidget); // 合計
    expect(find.textContaining('一年約 \$6,468'), findsOneWidget);
    expect(find.textContaining('訂閱 \$539・借款 \$0'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    // 每筆小字：左邊已經有幾號了，不再寫下次繳款日，只留「還有幾天」。
    expect(find.textContaining('下次'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^(還有 \d+ 天|今天繳款)$').hasMatch(w.data ?? ''),
      ),
      findsNWidgets(2),
    );
    // 扣款日 3 號的 Spotify 排在 12 號的 Netflix 前面。
    expect(
      tester.getTopLeft(find.text('Spotify')).dy,
      lessThan(tester.getTopLeft(find.text('Netflix')).dy),
    );
    final repo = LedgerRepository(store);
    var subs = (await tester.runAsync(() => repo.loadSubscriptions()))!;
    expect(subs.map((s) => '${s.name}${s.day}'), ['Spotify3', 'Netflix12']);

    // 表單裡沒有「扣款中」開關（2026-11-06 使用者）；每筆下面也沒有黃字。
    await tester.tap(find.text('Netflix'));
    await settle(tester);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('扣款中'), findsNothing);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    // 刪除 Spotify（要確認）。
    await tester.tap(find.text('Spotify'));
    await settle(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '刪除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    subs = (await tester.runAsync(() => repo.loadSubscriptions()))!;
    expect(subs.map((s) => s.name), ['Netflix']);
    expect(find.text('每月扣款合計・扣款中 1 項'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 只是紀錄：不會自動多出任何一筆交易。
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    expect(book.txs.length, 3);
  });

  testWidgets('每月扣款：可以標訂閱或借款，合計分開寫，改類型也行；欄位標題跟輸入框同一行', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerSubsPage(), store);
    await tester.tap(find.byTooltip('新增每月扣款'));
    await settle(tester);
    // 預設是訂閱；標題跟輸入框同一行（不是標題一行、輸入框下一行）。
    expect(find.text('服務名稱'), findsOneWidget);
    expect(
      (tester.getCenter(find.text('服務名稱')).dy -
              tester.getCenter(find.byType(TextField).at(0)).dy)
          .abs(),
      lessThan(6),
    );
    expect(
      (tester.getCenter(find.text('每月扣多少')).dy -
              tester.getCenter(find.byType(TextField).at(1)).dy)
          .abs(),
      lessThan(6),
    );
    // 這頁所有輸入框都不放提示字（2026-11-06 使用者）。
    List<String?> hints() => [
      for (final f in tester.widgetList<TextField>(find.byType(TextField)))
        f.decoration?.hintText,
    ];
    expect(hints().every((h) => h == null || h.isEmpty), isTrue);
    // 切到借款：標題跟提示文字跟著變，預設信用卡；金額欄改叫「月付金」。
    await tester.tap(kindSeg('借款'));
    await tester.pump();
    await tester.tap(typeSeg('小額借款'));
    await tester.pump();
    expect(hints().every((h) => h == null || h.isEmpty), isTrue);
    await tester.tap(typeSeg('信用卡'));
    await tester.pump();
    expect(find.text('月付金'), findsOneWidget);
    expect(find.text('每月扣多少'), findsNothing);
    expect(find.text('借款名稱'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '手機分期');
    await tester.enterText(find.byType(TextField).at(1), '1200');
    await tester.enterText(find.byType(TextField).at(2), '20');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final repo = LedgerRepository(store);
    var subs = (await tester.runAsync(() => repo.loadSubscriptions()))!;
    expect(subs.single.kind, LedgerChargeKind.debt);
    expect(
      find.textContaining('訂閱 \$0・借款 \$1,200・一年約 \$14,400'),
      findsOneWidget,
    );
    expect(find.text('信用卡'), findsOneWidget); // 列表上的標示
    // 改成訂閱：合計跟著搬過去。
    await tester.tap(find.text('手機分期'));
    await settle(tester);
    await tester.tap(kindSeg('訂閱'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle(tester);
    subs = (await tester.runAsync(() => repo.loadSubscriptions()))!;
    expect(subs.single.kind, LedgerChargeKind.subscription);
    expect(find.textContaining('訂閱 \$1,200・借款 \$0'), findsOneWidget);
    // 操作紀錄寫出類型的變化。
    final log = (await tester.runAsync(() => repo.loadLog()))!;
    expect(
      log.firstWhere((e) => e.action == '編輯扣款').detail,
      contains('類型：信用卡 → 訂閱'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('借款有期數跟貸款總額：表單算本利總額、純利息、實際年利率；列表也寫出來', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerSubsPage(), store);
    await tester.tap(find.byTooltip('新增每月扣款'));
    await settle(tester);
    // 訂閱沒有期數、貸款總額這幾列。
    expect(find.text('總期數'), findsNothing);
    expect(find.text('貸款總額'), findsNothing);
    await tester.tap(kindSeg('借款'));
    await tester.pump();
    expect(find.text('貸款總額'), findsOneWidget);
    // 預設信用卡：沒有期數、沒有第一期（2026-11-06 使用者）；小額借款、信貸才有。
    expect(find.text('總期數'), findsNothing);
    expect(find.text('第一期繳款日'), findsNothing);
    await tester.tap(typeSeg('小額借款'));
    await tester.pump();
    expect(find.text('總期數'), findsOneWidget);
    expect(find.text('第一期繳款日'), findsOneWidget);
    // 說明清楚第一期填的是什麼：第一次要繳款的那天（繳納期限），不是開始計息日。
    expect(find.textContaining('第一次要繳款的那天'), findsOneWidget);
    expect(find.textContaining('不是開始計息的日子'), findsOneWidget);
    // TextField 順序：名稱(0)、月付金(1)、每月幾號(2)、貸款總額(3)、手續費(4)、總期數(5)、備註(6)。
    await tester.enterText(find.byType(TextField).at(0), '手機分期');
    await tester.enterText(find.byType(TextField).at(1), '1000');
    await tester.enterText(find.byType(TextField).at(2), '10');
    await tester.enterText(find.byType(TextField).at(3), '11000');
    await tester.enterText(find.byType(TextField).at(4), '1000'); // 手續費內扣
    await tester.enterText(find.byType(TextField).at(5), '12');
    await tester.pump();
    // 12 期 × 1000 = 12000，比貸款總額 11000 多 1000（純利息）；手續費 1000 內扣，
    // 實際只拿到 10000，年利率拿實際拿到的錢算（含手續費）。
    final rate = loanAnnualRate(10000, 1000, 12)!.toStringAsFixed(2);
    final rateNoFee = loanAnnualRate(11000, 1000, 12)!.toStringAsFixed(2);
    expect(rate == rateNoFee, isFalse);
    // 分析放在備註下面，排成一張「分析」表：左邊項目、右邊數字。
    expect(find.text('分析'), findsOneWidget);
    expect(find.text('實際拿到'), findsOneWidget);
    expect(find.text('\$10,000'), findsOneWidget);
    expect(find.text('實際本利總額'), findsOneWidget);
    expect(find.text('\$12,000'), findsOneWidget);
    expect(find.text('純利息'), findsOneWidget);
    expect(find.text('\$1,000'), findsOneWidget); // 純利息
    expect(find.text('實際年利率'), findsOneWidget);
    expect(find.text('$rate%'), findsOneWidget);
    // 手續費 1000 占貸款總額 11000 → 9.09%（手續費金額本身不重複寫）。
    expect(find.text('手續費占貸款總額'), findsOneWidget);
    expect(find.text('9.09%'), findsOneWidget);
    // 分析表在備註的下面。
    expect(
      tester.getTopLeft(find.text('分析')).dy,
      greaterThan(tester.getTopLeft(find.text('備註')).dy),
    );
    // 標題跟輸入框同一行。
    expect(
      (tester.getCenter(find.text('貸款總額')).dy -
              tester.getCenter(find.byType(TextField).at(3)).dy)
          .abs(),
      lessThan(8),
    );
    // 借款表單比較長，新增鈕要先捲到看得到。
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final repo = LedgerRepository(store);
    final s = (await tester.runAsync(() => repo.loadSubscriptions()))!.single;
    expect(s.kind, LedgerChargeKind.debt);
    expect(s.periods, 12);
    expect(s.loanTotal, 11000);
    expect(s.fee, 1000);
    expect(s.startMonth, isNull);
    expect(s.debtType, LedgerDebtType.smallLoan);
    // 每筆下面不寫期數、貸款總額、利息這些黃字（2026-11-06 使用者：壓力很大）。
    expect(find.textContaining('共 12 期'), findsNothing);
    expect(find.textContaining('貸款總額'), findsNothing);
    expect(find.textContaining('純利息'), findsNothing);
    expect(find.textContaining('實際年利率'), findsNothing);
    // 改回訂閱：期數、貸款總額清掉，不留在資料裡。
    await tester.tap(find.text('手機分期'));
    await settle(tester);
    await tester.tap(kindSeg('訂閱'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle(tester);
    final back = (await tester.runAsync(
      () => repo.loadSubscriptions(),
    ))!.single;
    expect(back.kind, LedgerChargeKind.subscription);
    expect(back.periods, isNull);
    expect(back.loanTotal, isNull);
    final log = (await tester.runAsync(() => repo.loadLog()))!;
    final edit = log.firstWhere((e) => e.action == '編輯扣款');
    expect(edit.detail, contains('類型：小額借款 → 訂閱'));
    expect(edit.detail, contains('總期數：12 → （空）'));
    expect(edit.detail, contains('貸款總額：\$11000 → （空）'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('信貸也有第一期，只選年月不用時分；切到信用卡第一期就清掉', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerSubsPage(), store);
    await tester.tap(find.byTooltip('新增每月扣款'));
    await settle(tester);
    await tester.tap(kindSeg('借款'));
    await tester.pump();
    await tester.tap(typeSeg('信貸'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '銀行信貸');
    await tester.enterText(find.byType(TextField).at(1), '8699');
    await tester.enterText(find.byType(TextField).at(2), '5');
    await tester.enterText(find.byType(TextField).at(3), '100000');
    await tester.enterText(find.byType(TextField).at(5), '12');
    await tester.pump();
    final pick = find.textContaining('第一次要繳款是哪天');
    await tester.ensureVisible(pick);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();
    // 滾輪選到年月日：有「今天／昨天」，沒有「現在」，也沒有時分。
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('現在'), findsNothing);
    expect(find.text('這個月'), findsNothing);
    expect(find.text(':'), findsNothing);
    expect(find.text('日'), findsNothing);
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('（點一下改）'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final repo = LedgerRepository(store);
    var s = (await tester.runAsync(() => repo.loadSubscriptions()))!.single;
    expect(s.debtType, LedgerDebtType.personalLoan);
    expect(s.startMonth, dateKeyOf(DateTime.now()));
    // 選了第一期繳款日，每月幾號跟著帶入。
    expect(s.day, DateTime.now().day);
    expect(find.text('信貸'), findsOneWidget); // 列表上的標示
    // 列表不寫利率；資料裡 10 萬、每月 8,699、12 期 → 約 8%。
    expect(annualRateOf(s), closeTo(8.0, 0.05));
    // 改成信用卡：第一期清掉。
    await tester.tap(find.text('銀行信貸'));
    await settle(tester);
    await tester.tap(typeSeg('信用卡'));
    await tester.pump();
    expect(find.text('第一期'), findsNothing);
    final save = find.widgetWithText(FilledButton, '儲存');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
    s = (await tester.runAsync(() => repo.loadSubscriptions()))!.single;
    expect(s.debtType, LedgerDebtType.creditCard);
    expect(s.startMonth, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每月扣款：繳款網址（可開、可複製）、繳款戶頭（可複製）、備註可多行', (tester) async {
    final store = await seeded();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester, const LedgerSubsPage(), store);
    await tester.tap(find.byTooltip('新增每月扣款'));
    await settle(tester);
    // 沒填時表單沒有開啟／複製鈕。
    expect(find.byTooltip('開啟繳款網址'), findsNothing);
    expect(find.byTooltip('複製戶頭'), findsNothing);
    // TextField 順序：名稱(0)、每月扣多少(1)、每月幾號(2)、繳款網址(3)、繳款戶頭(4)、備註(5)。
    await tester.enterText(find.byType(TextField).at(0), '電信費');
    await tester.enterText(find.byType(TextField).at(1), '599');
    await tester.enterText(find.byType(TextField).at(2), '5');
    await tester.enterText(
      find.byType(TextField).at(3),
      'pay.example.com/login',
    );
    await tester.enterText(find.byType(TextField).at(4), '０８１２３４５６７８');
    await tester.enterText(find.byType(TextField).at(5), '第一行\n第二行\n第三行');
    await tester.pump();
    // 全形數字自動轉半形；填了就出現開啟／複製鈕。
    expect(
      tester.widget<TextField>(find.byType(TextField).at(4)).controller!.text,
      '0812345678',
    );
    expect(find.byTooltip('開啟繳款網址'), findsOneWidget);
    expect(find.byTooltip('複製網址'), findsOneWidget);
    await tester.tap(find.byTooltip('複製戶頭'));
    await tester.pump();
    expect(copied, ['0812345678']);
    // 備註是多行輸入框（一行塞不下會長高、可以換行）。
    final note = tester.widget<TextField>(find.byType(TextField).at(5));
    expect(note.maxLines, isNull);
    expect(note.keyboardType, TextInputType.multiline);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final repo = LedgerRepository(store);
    final s = (await tester.runAsync(() => repo.loadSubscriptions()))!.single;
    expect(s.payUrl, 'pay.example.com/login');
    expect(s.payAccount, '0812345678');
    expect(s.note, '第一行\n第二行\n第三行');
    // 列表：備註完整顯示、有幾行顯示幾行；有繳款頁／複製鈕。
    expect(find.text('第一行\n第二行\n第三行'), findsOneWidget);
    expect(find.text('繳款頁'), findsOneWidget);
    expect(find.text('複製網址'), findsOneWidget);
    await tester.tap(find.text('複製戶頭'));
    await tester.pump();
    expect(copied.last, '0812345678');
    expect(find.text('已複製戶頭'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    // 操作紀錄寫出繳款網址跟戶頭。
    final log = (await tester.runAsync(() => repo.loadLog()))!;
    final add = log.firstWhere((e) => e.action == '新增扣款');
    expect(add.detail, contains('繳款網址：pay.example.com/login'));
    expect(add.detail, contains('繳款戶頭：0812345678'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('每月扣款可以篩選全部／訂閱／借款，只影響列表不影響最上面的合計', (tester) async {
    final store = await seeded();
    await tester.runAsync(() async {
      final repo = LedgerRepository(store);
      await repo.addSubscription(name: 'Netflix', amount: 390, day: 12);
      await repo.addSubscription(
        name: '信用卡費',
        amount: 2000,
        day: 5,
        kind: LedgerChargeKind.debt,
        debtType: LedgerDebtType.creditCard,
      );
    });
    await pump(tester, const LedgerSubsPage(), store);
    expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('信用卡費'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '訂閱'));
    await tester.pump();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('信用卡費'), findsNothing);
    // 最上面的合計還是全部（390 + 2000）。
    expect(find.text('\$2,390'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '借款'));
    await tester.pump();
    expect(find.text('Netflix'), findsNothing);
    expect(find.text('信用卡費'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pump();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('信用卡費'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('借款算得出已繳幾期：列表寫已繳／共幾期、剩幾期；全部繳完變已繳清不算合計', (tester) async {
    final store = await seeded();
    final now = DateTime.now();
    // 從 3 個月前開始，每月 1 號、共 12 期 → 已繳 4 期（含這個月 1 號）。
    final start = DateTime(now.year, now.month - 3);
    await tester.runAsync(() async {
      final repo = LedgerRepository(store);
      await repo.addSubscription(
        name: '手機分期',
        amount: 1000,
        day: 1,
        kind: LedgerChargeKind.debt,
        periods: 12,
        loanTotal: 11000,
        startMonth: monthKeyOf(start),
      );
      // 已經扣完：從 5 個月前開始、共 3 期。
      await repo.addSubscription(
        name: '舊分期',
        amount: 500,
        day: 1,
        kind: LedgerChargeKind.debt,
        periods: 3,
        startMonth: monthKeyOf(DateTime(now.year, now.month - 5)),
      );
    });
    await pump(tester, const LedgerSubsPage(), store);
    // 每筆下面不寫已繳／剩幾期，只有一條進度條。
    expect(find.textContaining('已繳 4'), findsNothing);
    expect(find.textContaining('剩 8 期'), findsNothing);
    // 舊分期繳清了：不算進合計（只剩手機分期 1000），放在下面一區，寫已繳清。
    expect(find.text('每月扣款合計・扣款中 1 項'), findsOneWidget);
    expect(find.text('\$1,000'), findsWidgets);
    expect(find.textContaining('已繳清'), findsOneWidget);
    // 最上面卡片不寫借款總共還剩多少（2026-11-06 使用者：壓力很大）。
    expect(find.textContaining('借款還剩'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing); // 每筆下面沒有進度條（黑線）
    expect(tester.takeException(), isNull);
  });

  testWidgets('記一筆：上面那排沒有退款（退款在最下面）、別人還錢改叫收到欠款；退款開關切成退款', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    // 上面那排：支出、收入、轉帳、收到欠款；沒有退款、沒有「別人還錢」。
    expect(find.widgetWithText(ChoiceChip, '支出'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '收到欠款'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '退款'), findsNothing);
    expect(find.text('別人還錢'), findsNothing);
    // 退款開關在「跟別人一起」之下（整張表單最下面）。
    final pf = find.text('👥 跟別人一起（對方要給我錢）');
    final refund = find.text('↩ 退款');
    await tester.scrollUntilVisible(
      refund,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.getTopLeft(refund).dy, greaterThan(tester.getTopLeft(pf).dy));
    // 打開 → 切成退款（出現「退哪一筆」），關掉 → 回支出。
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(find.text('退哪一筆'), findsOneWidget);
    expect(find.text('👥 跟別人一起（對方要給我錢）'), findsNothing);
    await tester.scrollUntilVisible(
      refund,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(find.text('退哪一筆'), findsNothing);
    expect(find.text('👥 跟別人一起（對方要給我錢）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('記一筆：標題跟輸入框同一行（時間、商家、金額、備註）', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    double dy(Finder f) => tester.getCenter(f).dy;
    // TextField 順序：貼上(0)、商家(1)、金額(2)、備註在更下面。
    expect(
      (dy(find.text('商家／名稱')) - dy(find.byType(TextField).at(1))).abs(),
      lessThan(8),
    );
    expect(
      (dy(find.text('金額')) - dy(find.byType(TextField).at(2))).abs(),
      lessThan(8),
    );
    expect(
      (dy(find.text('時間')) - dy(find.byIcon(Icons.schedule_rounded))).abs(),
      lessThan(8),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('預設戶頭本來叫「中信活存」且沒被改過 → 自動改成「中信帳戶」，改過名的不動', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await tester.runAsync(() async {
      await repo.ensureDefaultAccounts();
    });
    // 模擬舊版：預設戶頭叫中信活存。
    final accts = (await tester.runAsync(() => repo.accountsForUpload()))!;
    final old = [
      for (final a in accts)
        a.id == 'default_bank'
            ? LedgerAccount(
                id: a.id,
                name: '中信活存',
                type: a.type,
                order: a.order,
                createdAt: a.createdAt,
                updatedAt: a.createdAt,
              )
            : a,
    ];
    await tester.runAsync(
      () => store.write(
        'ledger.accounts.v1',
        jsonEncode([for (final a in old) a.toJson()]),
      ),
    );
    var book = (await tester.runAsync(() => repo.loadBook()))!;
    expect(book.accountName('default_bank'), '中信帳戶');
    final log = (await tester.runAsync(() => repo.loadLog()))!;
    expect(log.where((e) => e.action == '帳戶改名').length, 1);
    // 再載入一次不會重複改名／記紀錄。
    book = (await tester.runAsync(() => repo.loadBook()))!;
    expect(
      (await tester.runAsync(
        () => repo.loadLog(),
      ))!.where((e) => e.action == '帳戶改名').length,
      1,
    );
    // 使用者自己改過名字（updatedAt 比 createdAt 晚）→ 就算叫中信活存也不動。
    final edited = [
      for (final a
          in await tester.runAsync(() => repo.accountsForUpload()) ??
              <LedgerAccount>[])
        a.id == 'default_bank'
            ? LedgerAccount(
                id: a.id,
                name: '中信活存',
                type: a.type,
                order: a.order,
                createdAt: a.createdAt,
                updatedAt: DateTime.now().add(const Duration(seconds: 5)),
              )
            : a,
    ];
    await tester.runAsync(
      () => store.write(
        'ledger.accounts.v1',
        jsonEncode([for (final a in edited) a.toJson()]),
      ),
    );
    book = (await tester.runAsync(() => repo.loadBook()))!;
    expect(book.accountName('default_bank'), '中信活存');
  });

  testWidgets('記一筆：商家輸入全形 ＦＯＯＤＰＡＮＤＡ 自動變 FOODPANDA（備註、搜尋也是）', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(2), '250');
    await tester.enterText(find.byType(TextField).at(1), 'ＦＯＯＤＰＡＮＤＡ　');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'FOODPANDA ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle(tester);
    final book = await tester.runAsync(
      () => LedgerRepository(store).loadBook(),
    );
    expect(book!.txs.any((t) => t.merchant == 'FOODPANDA'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('記帳首頁有「每月扣款」入口，寫每月合計跟幾項', (tester) async {
    final store = await seeded();
    await tester.runAsync(() async {
      final repo = LedgerRepository(store);
      await repo.addSubscription(name: 'Netflix', amount: 390, day: 12);
      await repo.addSubscription(name: 'iCloud', amount: 30, day: 31);
      await repo.addSubscription(
        name: '舊的',
        amount: 999,
        day: 1,
        active: false,
      );
    });
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    expect(find.text('每月扣款'), findsOneWidget);
    expect(find.text('2 項扣款中・每月 \$420'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(book!.accounts.map((a) => a.name), ['中信帳戶', '中信卡', '台新卡', '現金']);
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
    expect(find.text('⚠ 中信帳戶漏記 \$100'), findsOneWidget);
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
      if (tab == LedgerTab.list) {
        // 搜尋時不標（搜得到的都是有資料的）。
        await tester.enterText(find.byType(TextField).first, '鼎泰豐');
        await tester.pump();
        expect(find.textContaining('資料不準確'), findsNothing);
        await tester.tap(find.byTooltip('清除搜尋'));
        await tester.pump();
        expect(find.textContaining('資料不準確'), findsOneWidget);
      }
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
    // 品項名稱最多 50 字。
    await tester.enterText(find.byType(TextField).at(4), '字' * 60);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(4)).controller!.text,
      hasLength(ledgerSplitNameMax),
    );
    await tester.enterText(find.byType(TextField).at(4), '麵包');
    await tester.pump();
    // 品項名稱跟「幫人付」按鈕同一行。
    expect(
      (tester.getCenter(find.byType(TextField).at(4)).dy -
              tester
                  .getCenter(find.widgetWithText(FilterChip, '👥 幫人付').first)
                  .dy)
          .abs(),
      lessThan(8),
    );
    // 還沒標幫人付：沒有幫誰欄位。
    expect(find.byKey(const ValueKey('splitPeople1')), findsNothing);
    final chip = find.widgetWithText(FilterChip, '👥 幫人付').last;
    await tester.ensureVisible(chip);
    await tester.pump();
    // 底下有「新增」那條，再往上推一點才不會被蓋住。
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -150));
    await tester.pump();
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

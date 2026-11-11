import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/ledger_calc.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_glass_button.dart';
import 'package:lume/features/ledger/ledger_page.dart';

/// 2026-11-10 使用者：記一筆每個欄位都是「左邊標題｜右邊輸入」同一行、規格統一
/// （時間、商家、金額、帳戶、分類、這筆之後餘額、備註），金額也不特別長／特別大。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  timeUnknownTests();
  cardReturnTests();

  testWidgets('記一筆：標題都靠左同一條線；輸入框一樣高；帳戶、分類、餘額也是同一行', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await repo.addAccount(
      name: '中信活存',
      type: LedgerAccountType.bank,
      opening: 5000,
      openingAt: DateTime(2026, 11, 1),
    );
    await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 100,
      openingAt: DateTime(2026, 11, 1),
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.home)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
    await settle();
    await pickDefaultAccount(tester);
    await settle();

    double left(String t) => tester.getTopLeft(find.text(t).first).dx;
    double mid(Finder f) => tester.getCenter(f).dy;
    // 每個標題的左邊對齊同一條線。
    final x = left('時間');
    for (final t in ['來源', '金額', '備註', '進哪個帳戶', '分類']) {
      expect(left(t), closeTo(x, .5), reason: '標題「$t」要跟「時間」靠左對齊');
    }
    // 輸入框（時間、金額、備註）一樣高、一樣寬的起點。
    Finder box(String label) => find
        .ancestor(of: find.text(label).first, matching: find.byType(Row))
        .first;
    double h(String label) => tester.getSize(box(label)).height;
    expect(h('金額'), closeTo(h('備註'), 2));
    final amount = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0',
    );
    final memoLabel = find.text('備註');
    expect(tester.getSize(amount).height, lessThan(60), reason: '金額欄不特別高');
    // 金額標題跟它的輸入框同一行。
    expect((mid(find.text('金額')) - mid(amount)).abs(), lessThan(12));
    // 這筆之後的餘額：標題跟輸入框同一行（不分兩行）。
    await tester.ensureVisible(find.textContaining('這筆之後'));
    final after = find.textContaining('這筆之後').first;
    final afterField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.prefixText == r'$',
    );
    expect(afterField, findsWidgets);
    expect((mid(after) - mid(afterField.first)).abs(), lessThan(14));
    expect(memoLabel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 2026-11-10 使用者：時間不確定時只要選到天；時間旁邊有個按鈕，打開就代表不確定。
void timeUnknownTests() {
  test('時間不確定的同一天：1～20 在有時分的後面、21 以上在前面，數字大的在前；0 不算（跟沒設一樣）', () {
    LedgerTx u(String id, int order) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 8, 12),
      amount: 10,
      accountId: 'x',
      timeUnknown: true,
      timeOrder: order,
    );
    LedgerTx k(String id, int h, int m) => LedgerTx(
      id: id,
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 8, h, m),
      amount: 10,
      accountId: 'x',
    );
    final other = LedgerTx(
      id: 'next',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 9, 1),
      amount: 10,
      accountId: 'x',
    );
    final b = LedgerBook(
      accounts: const [],
      txs: [
        u('o3', 3),
        k('k0800', 8, 0),
        u('o25', 25),
        u('o10', 10),
        k('k1830', 18, 30),
        u('o99', 99),
        u('o0', 0),
        u('o21', 21),
        u('o20', 20),
        other,
      ],
      checkpoints: const [],
      budgets: const [],
    );
    // 隔天最上面；這天：超過 20 的（大→小）、有時分的（晚→早）、1～20 的（大→小）、沒設的最後。
    expect(b.txs.map((t) => t.id).toList(), [
      'next',
      'o99',
      'o25',
      'o21',
      'k1830',
      'k0800',
      'o20',
      'o10',
      'o3',
      'o0',
    ]);
    final t = u('a', 7);
    expect(LedgerTx.fromJson(t.toJson()).timeOrder, 7);
    expect(t.copyWith(amount: 1).timeOrder, 7);
    expect(u('b', 0).toJson().containsKey('timeOrder'), isFalse);
  });

  test('交易的「時間不確定」存得進、讀得回；沒開的不多存欄位', () {
    final t = LedgerTx(
      id: 'a',
      type: LedgerTxType.expense,
      occurredAt: DateTime(2026, 11, 8, 12),
      amount: 100,
      accountId: 'x',
      timeUnknown: true,
    );
    expect(LedgerTx.fromJson(t.toJson()).timeUnknown, isTrue);
    expect(t.copyWith(amount: 5).timeUnknown, isTrue);
    expect(t.copyWith(timeUnknown: false).timeUnknown, isFalse);
    expect(
      t.copyWith(timeUnknown: false).toJson().containsKey('timeUnknown'),
      isFalse,
    );
    // 舊資料沒有這個欄位＝時間是確定的。
    final old = t.toJson()..remove('timeUnknown');
    expect(LedgerTx.fromJson(old).timeUnknown, isFalse);
  });

  testWidgets('記一筆：時間旁邊的「不確定」打開後只顯示日期，存起來是那天中午、列表寫「時間不確定」', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 1000,
      openingAt: DateTime(2026, 11, 1),
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    final chip = find.byKey(const ValueKey('timeUnknown'));
    expect(chip, findsOneWidget);
    // 一開始有時分、沒有排序欄。
    expect(find.byKey(const ValueKey('timeOrder')), findsNothing);
    expect(find.textContaining(RegExp(r'\d\d:\d\d')), findsWidgets);
    await tester.tap(chip);
    await settle();
    expect(tester.widget<LedgerGlassButton>(chip).selected, isTrue);
    // 時間欄只剩日期，不寫「不確定幾點」，也沒有時分。
    expect(find.textContaining('不確定幾點'), findsNothing);
    // 排序欄在時間同一行的右邊，不用說明文字。
    final order = find.byKey(const ValueKey('timeOrder'));
    expect(order, findsOneWidget);
    expect(find.text('同天排序'), findsNothing);
    expect(
      (tester.getCenter(order).dy - tester.getCenter(find.text('時間').last).dy)
          .abs(),
      lessThan(14),
      reason: '排序欄跟「時間」同一行',
    );
    // 從 1 開始、0 不算：打 0 會被去掉；打 3 就是 3。
    await tester.enterText(order, '0');
    await tester.pump();
    expect(tester.widget<TextField>(order).controller!.text, '');
    await tester.enterText(order, '03');
    await tester.pump();
    expect(tester.widget<TextField>(order).controller!.text, '3');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
      ),
      '120',
    );
    await tester.enterText(
      find.descendant(
        of: find
            .ancestor(of: find.text('商家／名稱'), matching: find.byType(Row))
            .first,
        matching: find.byType(TextField),
      ),
      '早餐店',
    );
    await tester.tap(find.textContaining('餐飲').first);
    await tester.pump();
    await pickDefaultAccount(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle();
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    final tx = book.txs.single;
    expect(tx.timeUnknown, isTrue);
    expect(tx.occurredAt.hour, 12);
    expect(tx.occurredAt.minute, 0);
    expect(tx.timeOrder, 3, reason: '排序數字存起來');
    expect(find.textContaining('時間不確定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('編輯：時間不確定的那筆打開「不確定」是亮的、關掉變回時分；確定時間的那筆可以改成不確定', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final acc = await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 1000,
      openingAt: DateTime(2026, 11, 1),
    );
    final now = DateTime.now();
    await repo.addTransaction(
      LedgerTx(
        id: 't1',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 12),
        amount: 80,
        accountId: acc.id,
        category: '餐飲',
        merchant: '早餐店',
        timeUnknown: true,
      ),
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.textContaining('早餐店').first);
    await settle();
    await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
    await settle();
    final chip = find.byKey(const ValueKey('timeUnknown'));
    expect(chip, findsOneWidget);
    expect(tester.widget<LedgerGlassButton>(chip).selected, isTrue);
    // 編輯也能設排序：填 25（超過 20＝排在有時分的前面）後儲存。
    final order = find.byKey(const ValueKey('timeOrder'));
    expect(order, findsOneWidget);
    await tester.enterText(order, '25');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '儲存'));
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle();
    final saved = (await tester.runAsync(() => repo.loadBook()))!.txs.single;
    expect(saved.timeUnknown, isTrue);
    expect(saved.timeOrder, 25);
    // 再開編輯：排序欄帶出 25；關掉「不確定」變回時分、排序欄消失。
    await tester.tap(find.textContaining('排序 25'));
    await settle();
    await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
    await settle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('timeOrder')))
          .controller!
          .text,
      '25',
    );
    await tester.tap(chip);
    await settle();
    expect(tester.widget<LedgerGlassButton>(chip).selected, isFalse);
    expect(find.byKey(const ValueKey('timeOrder')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// 2026-11-10 使用者：卡費要有地方可以改負數（退款、部分退款），金額最後面一個 ＋／− 按鈕。
void cardReturnTests() {
  testWidgets('每種類型都有金額最後的 −／＋：收入按「−」變支出、轉帳按「＋」兩個帳戶對調、還錢也有', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final bank = await repo.addAccount(
      name: '中信活存',
      type: LedgerAccountType.bank,
      opening: 5000,
      openingAt: DateTime(2026, 11, 1),
    );
    final cash = await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 100,
      openingAt: DateTime(2026, 11, 1),
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final toggle = find.byKey(const ValueKey('signToggle'));
    final amountField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
    );
    await settle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    // 還錢：有鈕、預設「＋」。
    await tester.tap(find.widgetWithText(ChoiceChip, '收到欠款'));
    await settle();
    expect(toggle, findsOneWidget);
    expect(find.text('＋'), findsOneWidget);
    // 收入：預設「＋」；按「−」變成支出，金額、來源不動，分類先放未分類。
    await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
    await settle();
    expect(find.text('＋'), findsOneWidget);
    await tester.enterText(amountField, '700');
    await tester.pump();
    await tester.tap(toggle);
    await settle();
    expect(find.text('−'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '支出')).selected,
      isTrue,
    );
    expect(tester.widget<TextField>(amountField).controller!.text, '700');
    // 轉帳：預設「−」，按「＋」兩個帳戶對調（標題也跟著變）。
    await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
    await settle();
    expect(find.text('−'), findsOneWidget);
    expect(find.text('從哪個帳戶'), findsOneWidget);
    await tester.tap(find.text('ATM 提款')); // 快捷：銀行 → 現金
    await settle();
    await tester.enterText(amountField, '300');
    await tester.tap(toggle);
    await settle();
    expect(find.text('＋'), findsOneWidget);
    expect(find.text('收款帳戶'), findsOneWidget);
    expect(find.text('從哪個帳戶轉來'), findsOneWidget);
    await pickDefaultAccount(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle();
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    final tx = book.txs.single;
    expect(tx.type, LedgerTxType.transfer);
    expect(tx.accountId, cash.id, reason: '「＋」：主帳戶（銀行）是收到錢的那邊，存成現金 → 銀行');
    expect(tx.toAccountId, bank.id);
    expect(tx.amount, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡費：金額最後的 ＋／− 切成負數，存成信用卡 → 帳戶；列表寫負號跟「卡費退回」；編輯時還是負數', (
    tester,
  ) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final bank = await repo.addAccount(
      name: '中信活存',
      type: LedgerAccountType.bank,
      opening: 5000,
      openingAt: DateTime(2026, 11, 1),
    );
    final card = await repo.addAccount(
      name: '中信卡',
      type: LedgerAccountType.creditCard,
      opening: 3000,
      openingAt: DateTime(2026, 11, 1),
      creditLimit: 50000,
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
    await settle();
    // 轉帳也有 ＋／−（一般轉帳是「−」）。
    expect(find.byKey(const ValueKey('signToggle')), findsOneWidget);
    await tester.tap(find.text('繳卡費').first); // 快捷：帳戶 → 信用卡
    await settle();
    final toggle = find.byKey(const ValueKey('signToggle'));
    expect(toggle, findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    await tester.tap(toggle);
    await settle();
    expect(find.text('＋'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
      ),
      '500',
    );
    await tester.pump();
    await pickDefaultAccount(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await settle();
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    final tx = book.txs.single;
    expect(tx.type, LedgerTxType.transfer);
    expect(tx.accountId, card.id, reason: '卡費退回：從信用卡出');
    expect(tx.toAccountId, bank.id, reason: '回到帳戶');
    expect(tx.amount, 500);
    expect(tx.merchant, '卡費退回');
    expect(book.isCardReturn(tx), isTrue);
    // 帳戶：銀行 +500、信用卡欠款 +500。
    expect(
      LedgerBook.delta(tx, book.accounts.firstWhere((a) => a.id == bank.id)),
      500,
    );
    expect(
      LedgerBook.delta(tx, book.accounts.firstWhere((a) => a.id == card.id)),
      500,
    );
    expect(find.textContaining('卡費退回'), findsWidgets);
    expect(find.text('+\$500'), findsWidgets);
    // 編輯：負數還是亮的，帳戶回到「帳戶 → 信用卡」的填法。
    await tester.tap(find.text('卡費退回').first);
    await settle();
    await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
    await settle();
    expect(find.text('＋'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('signToggle')));
    await settle();
    expect(find.text('−'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '儲存'));
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle();
    final after = (await tester.runAsync(() => repo.loadBook()))!.txs.single;
    expect(after.accountId, bank.id, reason: '改回正數＝正常繳卡費：帳戶 → 信用卡');
    expect(after.toAccountId, card.id);
    expect(after.merchant, '繳卡費');
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷卡金額最後的 −／＋：預設「−」是消費，按成「＋」就是退刷（退款）；編輯舊的也能切', (tester) async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final card = await repo.addAccount(
      name: '中信卡',
      type: LedgerAccountType.creditCard,
      opening: 3000,
      openingAt: DateTime(2026, 11, 1),
      creditLimit: 50000,
    );
    final now = DateTime.now();
    await repo.addTransaction(
      LedgerTx(
        id: 'orig',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 9),
        amount: 800,
        accountId: card.id,
        category: '生活',
        merchant: '家樂福',
      ),
    );
    await repo.addTransaction(
      LedgerTx(
        id: 'mistake',
        type: LedgerTxType.expense,
        occurredAt: DateTime(now.year, now.month, now.day, 10),
        amount: 300,
        accountId: card.id,
        category: '生活',
        merchant: '退刷記成消費',
      ),
    );
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    // 新增：支出一開始是「−」。
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    final toggle = find.byKey(const ValueKey('signToggle'));
    expect(toggle, findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    await tester.tap(toggle);
    await settle();
    expect(find.text('＋'), findsOneWidget);
    expect(find.text('退哪一筆'), findsWidgets, reason: '＋就是退款，要選退哪一筆');
    await tester.tap(toggle);
    await settle();
    expect(find.text('−'), findsOneWidget);
    // 關掉新增表單。
    await tester.tapAt(const Offset(10, 60));
    await settle();
    // 編輯：把「退刷記成消費」那筆按成「＋」，變成退款、金額不動、帳戶還是那張卡。
    await tester.tap(find.textContaining('退刷記成消費').first);
    await settle();
    await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
    await settle();
    expect(find.text('−'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('signToggle')));
    await settle();
    expect(find.text('＋'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '儲存'));
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle();
    final book = (await tester.runAsync(() => repo.loadBook()))!;
    final fixed = book.txs.firstWhere((t) => t.id == 'mistake');
    expect(fixed.type, LedgerTxType.refund);
    expect(fixed.amount, 300);
    expect(fixed.accountId, card.id);
    expect(fixed.linkedId, isNotNull, reason: '退款連到某一筆支出');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '轉帳「轉到」多了 LineBank、他人戶頭：轉到 LineBank 只扣這邊的錢、不算支出（平轉）；他人戶頭＝轉給別人算支出',
    (tester) async {
      final store = _MemoryStore();
      final repo = LedgerRepository(store);
      final bank = await repo.addAccount(
        name: '中信活存',
        type: LedgerAccountType.bank,
        opening: 5000,
        openingAt: DateTime(2026, 11, 1),
      );
      await repo.addAccount(
        name: '現金',
        type: LedgerAccountType.cash,
        opening: 0,
        openingAt: DateTime(2026, 11, 1),
      );
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: const MaterialApp(home: LedgerPage(tab: LedgerTab.list)),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final amountField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '0' && w.key == null,
      );
      await settle();
      await tester.tap(find.byType(FloatingActionButton));
      await settle();
      await tester.tap(find.widgetWithText(ChoiceChip, '轉帳'));
      await settle();
      final lineBank = find.byKey(const ValueKey('toLineBank'));
      expect(lineBank, findsOneWidget);
      expect(find.byKey(const ValueKey('toOtherAccount')), findsOneWidget);
      // 從中信活存轉到 LineBank。
      await tester.tap(find.textContaining('中信活存').first);
      await settle();
      await tester.ensureVisible(lineBank);
      await tester.tap(lineBank);
      await settle();
      expect(tester.widget<ChoiceChip>(lineBank).selected, isTrue);
      await tester.enterText(amountField, '800');
      await tester.pump();
      await pickDefaultAccount(tester);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '新增'));
      await tester.tap(find.widgetWithText(FilledButton, '新增'));
      await settle();
      final book = (await tester.runAsync(() => repo.loadBook()))!;
      final tx = book.txs.single;
      expect(tx.type, LedgerTxType.transfer);
      expect(tx.accountId, bank.id);
      expect(tx.toAccountId, isNull);
      expect(tx.toName, 'LineBank');
      expect(tx.merchant, '平轉');
      // 轉出的帳戶餘額要被扣掉：5000 − 800；也不算支出。
      expect(
        book.stateOf(book.accounts.firstWhere((a) => a.id == bank.id))!.now,
        4200,
      );
      expect(book.statsWhere((_) => true).spend, 0);
      expect(find.textContaining('LineBank'), findsWidgets);
      expect(find.text('平轉'), findsWidgets);
      // 編輯：LineBank 還是選著的。
      await tester.tap(find.textContaining('LineBank').first);
      await settle();
      await tester.tap(find.widgetWithText(OutlinedButton, '編輯'));
      await settle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('toLineBank')))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
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

/// 2026-11-11 起新記的不預選帳戶（使用者：不要預設選中信卡）：測試照以前的預設自己點
/// （支出＝第一張信用卡、收入＝第一個戶頭；轉帳照舊會自己帶）。已經選了就不動。
Future<void> pickDefaultAccount(WidgetTester tester) async {
  bool on(String t) => tester
      .widgetList<ChoiceChip>(find.widgetWithText(ChoiceChip, t))
      .any((c) => c.selected);
  if (on('轉帳')) return;
  final income = on('收入');
  final title = find.text(income ? '進哪個帳戶' : '用哪個付');
  if (title.evaluate().isEmpty) return;
  final row = find.ancestor(of: title.first, matching: find.byType(Row)).first;
  final chips = find.descendant(of: row, matching: find.byType(ChoiceChip));
  final list = tester.widgetList<ChoiceChip>(chips).toList();
  if (list.isEmpty || list.any((c) => c.selected)) return;
  String label(ChoiceChip c) => (c.label as Text).data ?? '';
  var i = list.indexWhere((c) => label(c).startsWith(income ? '🏦' : '💳'));
  if (i < 0) i = 0;
  await tester.ensureVisible(chips.at(i));
  await tester.tap(chips.at(i));
  await tester.pump();
}

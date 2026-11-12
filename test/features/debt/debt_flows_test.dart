import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/debt_repository.dart';
import 'package:lume/domain/debt_schedule.dart';
import 'package:lume/domain/models/debt.dart';
import 'package:lume/features/debt/debt_data.dart';
import 'package:lume/features/debt/debt_sheets.dart';

import '../../support/poke.dart';

/// 負債管理每個流程從頭走到存檔（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 新增（沒填完不能按、還款佔收入超過 40% 會提醒、信用卡只記帳單）、編輯、繳款（最後一期＝還清）、
/// 取消已繳（不是最新那期不行）、提前還清與取消、刪除（取消／確認）、收入、明細頁每個分頁、
/// 還款策略、全部紀錄。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(DebtRepository, MemoryStore)> host(
    WidgetTester tester,
    MemoryStore store,
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
    return (DebtRepository(store), store);
  }

  Future<DebtData> data(WidgetTester tester, DebtRepository r) async =>
      (await tester.runAsync(
        () async => DebtData(
          debts: await r.loadDebts(),
          payments: await r.loadPayments(),
          income: await r.loadIncome(),
        ),
      ))!;

  Debt loan({int term = 12, String name = '信貸', DateTime? first}) {
    final f = first ?? DateTime(DateTime.now().year, DateTime.now().month - 1);
    return Debt(
      id: '',
      name: name,
      lender: '',
      type: DebtType.loan,
      principal: 12000,
      rate: 0,
      term: term,
      firstYear: f.year,
      firstMonth: f.month,
      dueDay: 10,
      flexible: false,
      flexPay: 0,
    );
  }

  Future<Debt> addLoan(WidgetTester tester, MemoryStore store, Debt d) async =>
      (await tester.runAsync(() => DebtRepository(store).addDebt(d)))!;

  Future<void> tapFilled(WidgetTester tester, String text) async {
    final f = find.widgetWithText(FilledButton, text).last;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  testWidgets('新增：沒填完不能按；填完算出每月、超過收入 40% 提醒；存起來', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(() => DebtRepository(store).setIncome(10000));
    final empty = DebtData(debts: const [], payments: const [], income: 10000);
    final (repo, _) = await host(
      tester,
      store,
      (c, ref) => debtFormFlow(c, ref, empty),
    );
    expect(find.text('新增債務'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), '車貸');
    await tester.enterText(f.at(1), '120000');
    await tester.enterText(f.at(2), '3');
    await tester.enterText(f.at(3), '12');
    await tester.enterText(f.at(4), '2000');
    await tester.pump();
    expect(find.textContaining('每月要繳'), findsWidgets);
    expect(find.textContaining('超過 40%'), findsOneWidget);
    // 扣款日 0／32 不行（邊界）。
    await tester.enterText(f.at(5), '32');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新增'))
          .onPressed,
      isNull,
    );
    await tester.enterText(f.at(5), '5');
    await tester.pump();
    await tapFilled(tester, '新增');
    final d = (await data(tester, repo)).stats.single.debt;
    expect(d.name, '車貸');
    expect(d.fee, 2000);
    expect(d.dueDay, 5);
    expect(find.textContaining('已新增債務：車貸'), findsOneWidget);
  });

  testWidgets('新增信用卡：只填名稱跟這期帳單', (tester) async {
    final store = MemoryStore();
    final empty = DebtData(debts: const [], payments: const [], income: null);
    final (repo, _) = await host(
      tester,
      store,
      (c, ref) => debtFormFlow(c, ref, empty),
    );
    await tester.tap(find.textContaining('信用卡'));
    await tester.pump();
    expect(find.text('這期帳單大概多少'), findsOneWidget);
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), '中信卡');
    await tester.enterText(f.at(1), '5000');
    await tester.pump();
    expect(find.textContaining('信用卡只記每期帳單'), findsOneWidget);
    await tapFilled(tester, '新增');
    final d = (await data(tester, repo)).stats.single.debt;
    expect(d.type, DebtType.card);
    expect(d.flexPay, 5000);
  });

  testWidgets('編輯：改名字存起來；按外面關掉＝不改', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan());
    final repo = DebtRepository(store);
    final dd = await data(tester, repo);
    await host(tester, store, (c, ref) => debtFormFlow(c, ref, dd, edit: d));
    expect(find.text('編輯債務'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '改名的信貸');
    await tester.pump();
    await tapFilled(tester, '儲存');
    expect((await data(tester, repo)).stats.single.debt.name, '改名的信貸');
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect((await data(tester, repo)).stats.single.debt.name, '改名的信貸');
  });

  testWidgets('繳款：確認已繳 → 記一筆；只有一期＝繳完跳「還清了」', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan(term: 2));
    final repo = DebtRepository(store);
    var s = (await data(tester, repo)).statsOf(d.id)!;
    await host(tester, store, (c, ref) => payFlow(c, ref, s));
    expect(find.text('確認已繳'), findsOneWidget);
    await tapFilled(tester, '確認已繳');
    expect((await data(tester, repo)).payments, hasLength(1));
    expect(find.textContaining('已繳'), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
    s = (await data(tester, repo)).statsOf(d.id)!;
    await host(tester, store, (c, ref) => payFlow(c, ref, s));
    // 金額清空不能按（邊界）。
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '確認已繳'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).first, '6000');
    await tester.pump();
    await tapFilled(tester, '確認已繳');
    expect(find.text('太好了'), findsOneWidget);
    await tester.tap(find.text('太好了'));
    await settle(tester);
    // 還清了＝沒有下一期，再按繳款不做事。
    s = (await data(tester, repo)).statsOf(d.id)!;
    expect(s.closed, isTrue);
    await host(tester, store, (c, ref) => payFlow(c, ref, s));
    expect(find.text('確認已繳'), findsNothing);
  });

  testWidgets('取消已繳：不是最新那期不行；最新那期確認後變回未繳；沒繳過不做事', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan());
    final repo = DebtRepository(store);
    var s = (await data(tester, repo)).statsOf(d.id)!;
    await host(tester, store, (c, ref) => cancelLatestFlow(c, ref, s));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.runAsync(() async {
      await repo.addPayment(
        debtId: d.id,
        date: DateTime.now(),
        amount: 1000,
        period: 1,
      );
      await repo.addPayment(
        debtId: d.id,
        date: DateTime.now(),
        amount: 1000,
        period: 2,
      );
    });
    s = (await data(tester, repo)).statsOf(d.id)!;
    await host(
      tester,
      store,
      (c, ref) => cancelLatestFlow(c, ref, s, period: 1),
    );
    expect(find.text('只能取消最新的那一期'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await host(
      tester,
      store,
      (c, ref) => cancelLatestFlow(c, ref, s, period: 2),
    );
    expect(find.text('取消這筆已繳？'), findsOneWidget);
    await tester.tap(find.text('取消已繳'));
    await settle(tester);
    expect((await data(tester, repo)).payments, hasLength(1));
    expect(find.text('已取消，變回未繳'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('提前還清：確認 → 還清了；取消提前清償 → 回到還款中', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan());
    final repo = DebtRepository(store);
    var s = (await data(tester, repo)).statsOf(d.id)!;
    await host(tester, store, (c, ref) => payoffFlow(c, ref, s));
    expect(find.text('一次還清？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '還清'));
    await settle(tester);
    expect(find.text('太好了'), findsOneWidget);
    await tester.tap(find.text('太好了'));
    await settle(tester);
    s = (await data(tester, repo)).statsOf(d.id)!;
    expect(s.debt.payoffAt, isNotNull);
    await host(tester, store, (c, ref) => cancelLatestFlow(c, ref, s));
    expect(find.text('取消提前清償？'), findsOneWidget);
    await tester.tap(find.text('取消清償'));
    await settle(tester);
    expect((await data(tester, repo)).statsOf(d.id)!.debt.payoffAt, isNull);
  });

  testWidgets('刪除：取消不刪；確認才刪', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan());
    final repo = DebtRepository(store);
    final s = (await data(tester, repo)).statsOf(d.id)!;
    await host(tester, store, (c, ref) => deleteDebtFlow(c, ref, s));
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect((await data(tester, repo)).stats, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    expect((await data(tester, repo)).stats, isEmpty);
    expect(find.textContaining('已刪除'), findsOneWidget);
  });

  testWidgets('每月收入：取消不存；填了存起來；Enter 也能存', (tester) async {
    final store = MemoryStore();
    final (repo, _) = await host(
      tester,
      store,
      (c, ref) => editIncomeFlow(c, ref, null),
    );
    expect(find.text('每月收入'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(await tester.runAsync(repo.loadIncome), isNull);
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '45000');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle(tester);
    expect(await tester.runAsync(repo.loadIncome), 45000);
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '50000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(await tester.runAsync(repo.loadIncome), 50000);
  });

  testWidgets('明細：每個分頁點一次；繳款、取消已繳、提前還、編輯、刪除都接得上', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan());
    final repo = DebtRepository(store);
    await tester.runAsync(
      () => repo.addPayment(
        debtId: d.id,
        date: DateTime.now(),
        amount: 1000,
        period: 1,
      ),
    );
    Future<DebtStats> s() async => (await data(tester, repo)).statsOf(d.id)!;
    for (final view in DebtDetailView.values) {
      final st = await s();
      await host(
        tester,
        store,
        (c, ref) => openDebtFlow(c, ref, st, view: view),
      );
      await pokeSheet(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
    }
    // 提前還那頁：每月多還、一次多還。
    var st = await s();
    await host(
      tester,
      store,
      (c, ref) => openDebtFlow(c, ref, st, view: DebtDetailView.values[2]),
    );
    final fields = find.byType(TextField);
    if (fields.evaluate().isNotEmpty) {
      await tester.enterText(fields.first, '500');
      await tester.pump();
      if (fields.evaluate().length > 1) {
        await tester.enterText(fields.at(1), '3000');
        await tester.pump();
      }
    }
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    // 資料頁 → 編輯 → 開表單、按外面關掉。
    st = await s();
    await host(
      tester,
      store,
      (c, ref) => openDebtFlow(c, ref, st, view: DebtDetailView.info),
    );
    await tester.tap(find.text('編輯'));
    await settle(tester);
    expect(find.text('編輯債務'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    // 資料頁 → 刪除 → 確認。
    st = await s();
    await host(
      tester,
      store,
      (c, ref) => openDebtFlow(c, ref, st, view: DebtDetailView.info),
    );
    await tester.tap(find.text('刪除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    expect((await data(tester, repo)).stats, isEmpty);
  });

  testWidgets('月曆上點一期：沒繳＝開繳款；繳了＝取消', (tester) async {
    final store = MemoryStore();
    final d = await addLoan(tester, store, loan());
    final repo = DebtRepository(store);
    var s = (await data(tester, repo)).statsOf(d.id)!;
    await host(
      tester,
      store,
      (c, ref) => toggleDueFlow(c, ref, DueItem(s, s.next!)),
    );
    expect(find.text('確認已繳'), findsOneWidget);
    await tapFilled(tester, '確認已繳');
    await tester.pump(const Duration(seconds: 6));
    s = (await data(tester, repo)).statsOf(d.id)!;
    await host(
      tester,
      store,
      (c, ref) => toggleDueFlow(c, ref, DueItem(s, s.paid.last)),
    );
    expect(find.text('取消這筆已繳？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
  });

  testWidgets('還款策略、全部紀錄：沒有債務／有債務都開得起來', (tester) async {
    final store = MemoryStore();
    final d1 = await addLoan(tester, store, loan(name: 'A'));
    await addLoan(tester, store, loan(name: 'B', term: 24));
    final repo = DebtRepository(store);
    await tester.runAsync(
      () => repo.addPayment(
        debtId: d1.id,
        date: DateTime.now(),
        amount: 1000,
        period: 1,
      ),
    );
    final all = (await data(tester, repo)).stats;
    await host(tester, store, (c, _) => showStrategySheet(c, const []));
    expect(find.text('沒有還款中的債務'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await host(tester, store, (c, _) => showStrategySheet(c, all));
    await tester.enterText(find.byType(TextField).first, '2000');
    await tester.pump();
    await tester.tap(find.text('雪球法（金額小先還）'));
    await tester.pump();
    expect(find.text('順序'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await host(tester, store, (c, _) => showAllRecordsSheet(c, const []));
    expect(find.text('還沒有還款紀錄'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await host(tester, store, (c, _) => showAllRecordsSheet(c, all));
    expect(find.text('紀錄一筆都不刪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 底部表單裡每個分段按鈕、晶片都點一次（不關表單）。
Future<void> pokeSheet(WidgetTester tester) async {
  final segs = find.byWidgetPredicate(
    (w) =>
        w is ChoiceChip ||
        w is FilterChip ||
        w.runtimeType.toString().startsWith('SegmentedButton'),
  );
  for (var i = 0; i < segs.evaluate().length; i++) {
    await tester.tap(segs.at(i), warnIfMissed: false);
    await settle(tester, 1);
  }
}

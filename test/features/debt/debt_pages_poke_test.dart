import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/debt_repository.dart';
import 'package:lume/domain/models/debt.dart';
import 'package:lume/features/debt/debt_calendar_page.dart';
import 'package:lume/features/debt/debt_page.dart';

import '../../support/poke.dart';

/// 負債主頁四個分頁、還款月曆（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 有信貸、手機貸、信用卡、已還清、彈性還款時，每個按鈕、卡片、晶片都點一次不會壞。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MemoryStore> seeded(WidgetTester tester) async {
    final store = MemoryStore();
    final repo = DebtRepository(store);
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - 2);
    Debt d(
      String name,
      DebtType t,
      double p,
      double r,
      int term, {
      bool flex = false,
      double fp = 0,
      DateTime? payoff,
    }) => Debt(
      id: '',
      name: name,
      lender: '銀行',
      type: t,
      principal: p,
      rate: r,
      term: term,
      firstYear: first.year,
      firstMonth: first.month,
      dueDay: 5,
      flexible: flex,
      flexPay: fp,
      payoffAt: payoff,
      payoffAmount: payoff == null ? null : 1000,
    );
    await tester.runAsync(() async {
      final a = await repo.addDebt(d('信貸', DebtType.loan, 300000, 6.5, 60));
      await repo.addDebt(d('手機貸', DebtType.phone, 36000, 0, 12));
      await repo.addDebt(d('卡費', DebtType.card, 0, 0, 0, fp: 8000));
      await repo.addDebt(
        d('跟家人借', DebtType.other, 50000, 0, 0, flex: true, fp: 3000),
      );
      await repo.addDebt(d('已還清', DebtType.laptop, 20000, 0, 10, payoff: now));
      await repo.addPayment(debtId: a.id, date: first, amount: 5870, period: 1);
      await repo.addPayment(
        debtId: a.id,
        date: first.add(const Duration(days: 30)),
        amount: 5870,
        period: 2,
      );
      await repo.setIncome(60000);
    });
    return store;
  }

  for (final tab in ['本月', '債務', '試算', '總覽']) {
    testWidgets('負債主頁「$tab」：每個控制項點一次', (tester) async {
      final store = await seeded(tester);
      final router = await pumpPage(
        tester,
        store,
        () => const DebtPage(),
        size: const Size(390, 900),
      );
      await tester.tap(find.text(tab).last);
      await settle(tester);
      final n = await pokeAll(tester, router, max: 120);
      expect(n, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('還款月曆：上下個月、點每一天、點每一期', (tester) async {
    final store = await seeded(tester);
    final router = await pumpPage(
      tester,
      store,
      () => const DebtCalendarPage(),
      size: const Size(390, 900),
    );
    final n = await pokeAll(tester, router, max: 150);
    expect(n, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
  });
}

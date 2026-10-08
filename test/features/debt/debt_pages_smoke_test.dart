import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/debt_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/debt.dart';
import 'package:lume/features/debt/debt_calendar_page.dart';
import 'package:lume/features/debt/debt_page.dart';

/// 負債兩頁在手機寬度（360）畫得出來、不爆版，有資料跟沒資料都要。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_MemoryStore> seeded() async {
    final store = _MemoryStore();
    final repo = DebtRepository(store);
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - 3);
    Debt d(
      String name,
      DebtType t,
      double p,
      double r,
      int term, {
      bool flex = false,
      double fp = 0,
    }) => Debt(
      id: '',
      name: name,
      lender: '一個名字很長很長很長的銀行股份有限公司',
      type: t,
      principal: p,
      rate: r,
      term: term,
      firstYear: first.year,
      firstMonth: first.month,
      dueDay: 5,
      flexible: flex,
      flexPay: fp,
    );
    final a = await repo.addDebt(
      d('國泰信貸 名字也很長很長很長', DebtType.loan, 300000, 6.5, 60),
    );
    await repo.addDebt(d('iPhone 手機貸', DebtType.phone, 36000, 0, 12));
    await repo.addDebt(
      d('中信卡 名字很長很長很長很長', DebtType.card, 0, 0, 0, fp: 9999999),
    );
    await repo.addPayment(debtId: a.id, date: first, amount: 5870, period: 1);
    await repo.setIncome(60000);
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

  for (final empty in [false, true]) {
    final tag = empty ? '（沒資料）' : '（有資料）';

    testWidgets('四個分頁都畫得出來$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pump(tester, const DebtPage(), store);
      expect(find.text('負債總覽'), findsOneWidget);
      for (final t in ['本月', '債務', '試算', '總覽']) {
        await tester.tap(find.text(t).last);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: t);
      }
      if (empty) expect(find.text('還沒有債務'), findsOneWidget);
    });

    testWidgets('月曆檢視$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pump(tester, const DebtCalendarPage(), store);
      expect(find.text('還款月曆'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('新增債務表單填完才能存，即時算月付', (tester) async {
    await pump(tester, const DebtPage(), _MemoryStore());
    // FAB 有出場的縮放動畫，跑完才點得到。
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '新增'));
    expect(save().onPressed, isNull);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '測試信貸');
    await tester.enterText(fields.at(1), '100000');
    await tester.enterText(fields.at(2), '5');
    await tester.enterText(fields.at(3), '24');
    await tester.enterText(fields.at(4), '3000');
    await tester.pump();
    expect(find.textContaining('4,387'), findsOneWidget);
    // 開辦費 3,000＋利息約 5,290＝總成本
    expect(find.textContaining('8,29'), findsOneWidget);
    expect(save().onPressed, isNotNull);
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

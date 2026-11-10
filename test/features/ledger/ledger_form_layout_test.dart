import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';

/// 2026-11-10 使用者：記一筆每個欄位都是「左邊標題｜右邊輸入」同一行、規格統一
/// （時間、商家、金額、帳戶、分類、這筆之後餘額、備註），金額也不特別長／特別大。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

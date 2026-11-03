import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/i88_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/i88/i88_page.dart';

/// i88：手機寬度畫得出來，記一筆贏／輸、月曆看得到、算進本月、目標進度。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, _MemoryStore store) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: I88Page()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('沒資料也畫得出來；記一贏一輸，本月輸贏是兩個加起來', (tester) async {
    final store = _MemoryStore();
    await pump(tester, store);
    expect(tester.takeException(), isNull);
    expect(find.text('本月輸贏'), findsOneWidget);
    await tester.pumpAndSettle();

    Future<void> add(String amount, {bool lose = false}) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      if (lose) await tester.tap(find.text('輸'));
      await tester.enterText(find.byType(TextField).first, amount);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '記下來'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await add('1200');
    await add('500', lose: true);
    expect(tester.takeException(), isNull);
    final repo = I88Repository(store);
    final list = await tester.runAsync(() => repo.loadEntries());
    expect(list!.map((e) => e.amount).toSet(), {1200, -500});
    expect(find.text('+\$700'), findsWidgets);
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

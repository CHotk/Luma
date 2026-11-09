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

  testWidgets('記錄只到天：日期按鈕只有年月日，滾輪沒有時分，列表也不寫時間', (tester) async {
    final store = _MemoryStore();
    await pump(tester, store);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    // 日期按鈕只寫年月日。
    expect(find.text('${now.year}/${now.month}/${now.day}'), findsOneWidget);
    await tester.tap(find.text('${now.year}/${now.month}/${now.day}'));
    await tester.pumpAndSettle();
    // 滾輪沒有時分（沒有冒號、沒有「現在」）。
    expect(find.text(':'), findsNothing);
    expect(find.text('現在'), findsNothing);
    expect(find.text('今天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月曆下面的標籤：點了月曆亮出贏／輸／有記錄的日子，其他天變淡，再點取消', (tester) async {
    final store = _MemoryStore();
    final repo = I88Repository(store);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await repo.add(at: DateTime(now.year, now.month, 1, 12), amount: 500);
      await repo.add(at: DateTime(now.year, now.month, 2, 12), amount: -300);
      await repo.add(at: DateTime(now.year, now.month, 3, 12), amount: 200);
    });
    await pump(tester, store);
    final days = DateTime(now.year, now.month + 1, 0).day;
    expect(find.text('贏的日子 2'), findsOneWidget);
    expect(find.text('輸的日子 1'), findsOneWidget);
    expect(find.text('有記錄的日子 3'), findsOneWidget);
    int dimmed() => tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((o) => o.opacity == 0.25)
        .length;
    expect(dimmed(), 0);
    // 贏的日子：2 天亮，其他天變淡。
    await tester.ensureVisible(find.text('贏的日子 2'));
    await tester.tap(find.text('贏的日子 2'));
    await tester.pump();
    expect(dimmed(), days - 2);
    // 換成輸的日子：1 天亮。
    await tester.tap(find.text('輸的日子 1'));
    await tester.pump();
    expect(dimmed(), days - 1);
    await tester.tap(find.text('有記錄的日子 3'));
    await tester.pump();
    expect(dimmed(), days - 3);
    // 再點一次取消。
    await tester.tap(find.text('有記錄的日子 3'));
    await tester.pump();
    expect(dimmed(), 0);
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

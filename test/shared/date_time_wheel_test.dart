import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/widgets/date_time_wheel.dart';

/// 年月日時分一頁選完（原本日期、時間分兩頁很難用）。
void main() {
  Future<DateTime?> open(
    WidgetTester tester,
    DateTime initial,
    Future<void> Function() act,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    result = await showDateTimeWheel(c, initial),
                child: const Text('開'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    await act();
    return result;
  }

  testWidgets('一頁同時看到年月日時分，按確定回傳原本的時間', (tester) async {
    final t = DateTime(2026, 11, 5, 15, 30);
    final r = await open(tester, t, () async {
      expect(find.text('2026/11/5 15:30'), findsOneWidget);
      expect(find.text('2026年'), findsWidgets);
      expect(find.text('11月'), findsWidgets);
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
    });
    expect(r, t);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「昨天」「現在」快捷、取消不回傳', (tester) async {
    DateTime? r = DateTime(2000);
    final t = DateTime(2026, 11, 5, 15, 30);
    r = await open(tester, t, () async {
      await tester.tap(find.text('昨天'));
      await tester.pumpAndSettle();
      final y = DateTime.now().subtract(const Duration(days: 1));
      expect(
        find.textContaining('${y.year}/${y.month}/${y.day} 15:30'),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
    expect(r, isNull);
  });
}

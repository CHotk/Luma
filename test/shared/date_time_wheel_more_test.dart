import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/widgets/date_time_wheel.dart';

/// 日期滾輪的邊界（2026-11-13 第 19 項）：只選年月（「這個月」、回傳 1 號）、
/// 只選日期（「今天」「昨天」、回傳 0 點）、完整模式的「今天」保留時分；轉年月讓
/// 日超過月底（1/31 → 2 月）拉回月底、閏年；日轉到 31 但這個月只有 30 天停在月底；
/// 時、分滾輪；起始年份超出範圍夾回範圍內。
void main() {
  Future<DateTime?> open(
    WidgetTester tester,
    DateTime initial,
    Future<void> Function() act, {
    bool monthOnly = false,
    bool dateOnly = false,
    int minYear = 2020,
    int maxYear = 2035,
  }) async {
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
                onPressed: () async => result = await showDateTimeWheel(
                  c,
                  initial,
                  monthOnly: monthOnly,
                  dateOnly: dateOnly,
                  minYear: minYear,
                  maxYear: maxYear,
                ),
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
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    return result;
  }

  /// 第 [i] 個滾輪（年、月、日、時、分）轉到第 [item] 項。
  Future<void> spin(WidgetTester tester, int i, int item) async {
    final picker = tester.widget<CupertinoPicker>(
      find.byType(CupertinoPicker).at(i),
    );
    picker.scrollController!.jumpToItem(item);
    await tester.pumpAndSettle();
  }

  testWidgets('只選年月：兩個滾輪、「這個月」、回傳那個月 1 號', (tester) async {
    final r = await open(tester, DateTime(2024, 3, 17, 9, 5), () async {
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      expect(find.text('2024/3'), findsOneWidget);
      await spin(tester, 1, 6); // 7 月
      expect(find.text('2024/7'), findsOneWidget);
      await tester.tap(find.text('這個月'));
      await tester.pumpAndSettle();
      await spin(tester, 0, 5); // 2025 年
    }, monthOnly: true);
    expect(r!.year, 2025);
    expect(r.day, 1);
    expect(r.hour, 0);
  });

  testWidgets('只選日期：三個滾輪、「今天」「昨天」、回傳 0 點', (tester) async {
    final r = await open(tester, DateTime(2024, 3, 17, 9, 5), () async {
      expect(find.byType(CupertinoPicker), findsNWidgets(3));
      expect(find.text('2024/3/17'), findsOneWidget);
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('昨天'));
      await tester.pumpAndSettle();
    }, dateOnly: true);
    final y = DateTime.now().subtract(const Duration(days: 1));
    expect(r, DateTime(y.year, y.month, y.day));
  });

  testWidgets('完整模式「今天」：日期換今天、時分保留；時、分滾輪', (tester) async {
    final r = await open(tester, DateTime(2024, 3, 17, 9, 5), () async {
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      await spin(tester, 3, 22);
      await spin(tester, 4, 45);
    });
    final n = DateTime.now();
    expect(r, DateTime(n.year, n.month, n.day, 22, 45));
  });

  testWidgets('1/31 轉到 2 月：日拉回 2/29（閏年）；再轉到 2025 年變 2/28', (tester) async {
    final r = await open(tester, DateTime(2024, 1, 31, 8), () async {
      await spin(tester, 1, 1);
      expect(find.text('2024/2/29 08:00'), findsOneWidget);
      await spin(tester, 0, 5);
      expect(find.text('2025/2/28 08:00'), findsOneWidget);
    });
    expect(r, DateTime(2025, 2, 28, 8));
  });

  testWidgets('4 月的日滾輪轉到 31：停在 30', (tester) async {
    final r = await open(tester, DateTime(2026, 4, 10, 8), () async {
      await spin(tester, 2, 30);
      await tester.pump();
      expect(find.text('2026/4/30 08:00'), findsOneWidget);
    });
    expect(r, DateTime(2026, 4, 30, 8));
  });

  testWidgets('起始年份超出範圍：夾回範圍內', (tester) async {
    final r = await open(
      tester,
      DateTime(2050, 6, 1, 8),
      () async {},
      minYear: 2020,
      maxYear: 2030,
    );
    expect(r!.year, 2030);
  });
}

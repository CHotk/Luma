import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/jp_light/jp_bloom_celebration.dart';
import 'package:lume/features/jp_light/jp_light_data.dart';
import 'package:lume/features/kana_practice/gojuon_data.dart';

/// 開花慶祝（2026-10-16）：一朵的毛玻璃卡、10 朵的満開、存圖。
void main() {
  final now = DateTime.now();
  JpRowLight row(String r, {required bool lit}) => JpRowLight(
    row: r,
    litAt: lit ? now : null,
    firstAt: now.subtract(const Duration(days: 3)),
    practiceCount: 12,
    examTime: Duration.zero,
    exams: 2,
    best: lit ? 100 : 60,
    lastWrong: const [],
    bloomTimes: lit ? [now] : const [],
    attempts: 2,
  );
  final keys = gojuonRows.keys.toList();

  Future<void> open(WidgetTester tester, List<JpRowLight> lights, int i) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBloomCelebration(context, lights, lights[i]),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('第 3 朵：毛玻璃卡寫開花、三分咲き、記錄跟點亮下一行', (tester) async {
    final lights = [
      for (var i = 0; i < keys.length; i++) row(keys[i], lit: i < 3),
    ];
    expect(jpShouldCelebrate(lights[2]), isTrue);
    await open(tester, lights, 2);
    expect(find.text('さ行 開花！'), findsOneWidget);
    expect(find.textContaining('三分咲き'), findsWidgets);
    expect(find.text('📸 記錄'), findsOneWidget);
    expect(find.text('點亮 た行 →'), findsOneWidget);
    expect(find.text('好耶'), findsNothing);
  });

  testWidgets('10 朵全開：満開畫面', (tester) async {
    final lights = [for (final k in keys) row(k, lit: true)];
    await open(tester, lights, 9);
    expect(find.text('満開'), findsOneWidget);
    expect(find.text('📸 留個紀念'), findsOneWidget);
    expect(find.text('回到樹下'), findsOneWidget);
  });

  testWidgets('存圖畫得出 PNG', (tester) async {
    final lights = [
      for (var i = 0; i < keys.length; i++) row(keys[i], lit: i < 5),
    ];
    final png = await tester.runAsync(
      () => renderBloomKeepsake(lights, lights[4]),
    );
    expect(png, isNotNull);
    expect(png!.length, greaterThan(1000));
    expect(png.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
  });
}

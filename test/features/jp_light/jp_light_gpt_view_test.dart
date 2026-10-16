import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/jp_light/jp_light_data.dart';
import 'package:lume/features/jp_light/jp_light_gpt_view.dart';
import 'package:lume/features/kana_practice/gojuon_data.dart';

/// GPT 版櫻花樹（2026-10-16）：咲き進度條、小精靈對話不跑版、點一下換一句。
void main() {
  final now = DateTime.now();
  final keys = gojuonRows.keys.toList();
  List<JpRowLight> lights(int lit) => [
    for (var i = 0; i < keys.length; i++)
      JpRowLight(
        row: keys[i],
        litAt: i < lit ? now : null,
        firstAt: i <= lit ? now.subtract(const Duration(days: 2)) : null,
        practiceCount: 5,
        examTime: Duration.zero,
        exams: i <= lit ? 1 : 0,
        best: 0,
        lastWrong: i == lit ? const ['な'] : const [],
        bloomTimes: i < lit ? [now] : const [],
        attempts: i <= lit ? 2 : 0,
      ),
  ];

  for (final w in [360.0, 430.0]) {
    testWidgets('寬 $w：4 朵開、三分咲き、小精靈每一句都不跑版', (tester) async {
      tester.view.physicalSize = Size(w * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JpLightGptBody(lights: lights(4))),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('三分咲き'), findsOneWidget);
      final seen = <String>{};
      var sawWords = false;
      for (var k = 0; k < 6; k++) {
        await tester.tap(find.textContaining('點我換一句').last);
        await tester.pump(const Duration(milliseconds: 400));
        sawWords |= find.textContaining('能拼出').evaluate().isNotEmpty;
        seen.add(
          tester.widgetList<Text>(find.textContaining('點我換一句')).last.data!,
        );
      }
      expect(seen.length, greaterThan(1));
      expect(sawWords, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/kana_exam_repository.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/features/kana_exam/kana_exam_light_select_page.dart';
import 'package:lume/features/kana_exam/kana_exam_mode_select_page.dart';
import 'package:lume/features/kana_exam/kana_exam_row_select_page.dart';
import 'package:lume/features/kana_practice/gojuon_data.dart';

import '../../support/poke.dart';

/// 50 音考試的三個選擇頁（2026-11-13 第 15 項）：模式（50 音、詞彙、點亮、考試紀錄）；
/// 出題範圍（預設全選、單行切換、全取消時不能開始、全選、開始帶選的行）；點亮（沒資料
/// 預設あ行、開過あ行輪到か行、還沒輪到的鎖住點不了、看櫻花樹、開始帶那一行）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  Future<void> open(
    WidgetTester tester,
    Widget Function() page, [
    MemoryStore? store,
  ]) async {
    await pumpPage(
      tester,
      store ?? MemoryStore(),
      page,
      size: const Size(390, 1200),
    );
    await settle(tester, 4);
  }

  testWidgets('模式選擇：三種考試、考試紀錄', (tester) async {
    for (final (label, target) in [
      ('50 音', '/kana-exam/rows'),
      ('詞彙', '/kana-exam/start'),
      ('點亮', '/kana-exam/light'),
    ]) {
      await open(tester, () => const KanaExamModeSelectPage());
      await tester.tap(find.textContaining(label).first);
      await settle(tester, 3);
      expect(find.text('route:$target'), findsOneWidget, reason: label);
    }
    await open(tester, () => const KanaExamModeSelectPage());
    await tester.tap(find.byTooltip('考試紀錄'));
    await settle(tester, 3);
    expect(find.text('route:/kana-exam/history'), findsOneWidget);
  });

  testWidgets('出題範圍：預設全選、單行切換、全取消不能開始、全選、開始', (tester) async {
    FilledButton start() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '開始考試'));
    await open(tester, () => const KanaExamRowSelectPage());
    expect(start().onPressed, isNotNull);
    await tester.tap(find.text('全取消'));
    await settle(tester, 2);
    expect(start().onPressed, isNull);
    await tester.tap(find.text('か行'));
    await settle(tester, 2);
    expect(start().onPressed, isNotNull);
    await tester.tap(find.text('か行'));
    await settle(tester, 2);
    expect(start().onPressed, isNull);
    await tester.tap(find.text('全選'));
    await settle(tester, 2);
    await tester.tap(find.text('あ行'));
    await settle(tester, 2);
    await tester.tap(find.text('開始考試'));
    await settle(tester, 3);
    expect(find.text('route:/kana-exam/start'), findsOneWidget);
    expect(gojuonRows.length, 10);
  });

  testWidgets('點亮：沒資料預設あ行、看櫻花樹、開始', (tester) async {
    await open(tester, () => const KanaExamLightSelectPage());
    expect(find.textContaining('開始點亮 あ行（10 題）'), findsOneWidget);
    await tester.tap(find.text('看櫻花樹'));
    await settle(tester, 3);
    expect(find.text('route:/jp-light'), findsOneWidget);
    await open(tester, () => const KanaExamLightSelectPage());
    await tester.tap(find.textContaining('開始點亮'));
    await settle(tester, 3);
    expect(find.text('route:/kana-exam/start'), findsOneWidget);
  });

  testWidgets('點亮：開過あ行輪到か行；還沒輪到的鎖住；開過的可以再考', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final repo = KanaExamRepository(store);
      var i = 0;
      for (final (kana, romaji) in [
        ...gojuonRows['あ']!,
        ...gojuonRowsKatakana['あ']!,
      ]) {
        await repo.add(
          KanaExamEntry(
            id: '${i++}',
            roundId: 'r',
            kana: kana,
            romaji: romaji,
            isCorrect: true,
            examType: 'kana',
            savedAt: DateTime(2026, 10, 1, 8, i),
            lightRow: 'あ',
            strokes: const [],
          ),
        );
      }
    });
    await open(tester, () => const KanaExamLightSelectPage(), store);
    expect(find.textContaining('開始點亮 か行（20 題）'), findsOneWidget);
    // さ行還沒輪到：點了不動。
    expect(find.text('🔒 先點亮 か行'), findsWidgets);
    expect(find.text('🌸 已點亮'), findsOneWidget);
    await tester.tap(find.text('さ し す せ そ'), warnIfMissed: false);
    await settle(tester, 2);
    expect(find.textContaining('開始點亮 か行'), findsOneWidget);
    // あ行開過了，可以再考。
    await tester.tap(find.text('あ い う え お'));
    await settle(tester, 2);
    expect(find.textContaining('開始點亮 あ行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三頁 390 寬每個控制項點一次', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    for (final page in [
      () => const KanaExamModeSelectPage(),
      () => const KanaExamRowSelectPage(),
      () => const KanaExamLightSelectPage(),
    ]) {
      final r = await pumpPage(
        tester,
        MemoryStore(),
        page,
        size: const Size(390, 860),
      );
      await settle(tester, 4);
      await pokeAll(tester, r, max: 60);
      expect(tester.takeException(), isNull);
    }
  });
}

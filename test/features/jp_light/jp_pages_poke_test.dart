import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/jp_light_style_store.dart';
import 'package:lume/data/repositories/kana_exam_repository.dart';
import 'package:lume/data/repositories/kana_practice_repository.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/domain/models/kana_practice.dart';
import 'package:lume/features/jp_home/jp_home_page.dart';
import 'package:lume/features/jp_home/jp_log_page.dart';
import 'package:lume/features/jp_home/jp_stats_page.dart';
import 'package:lume/features/jp_light/jp_light_page.dart';
import 'package:lume/features/kana_practice/gojuon_data.dart';
import 'package:lume/shared/widgets/sakura_petals.dart';

import '../../support/poke.dart';

/// 日文首頁、統計、練習紀錄、櫻花樹（2026-11-13 第 16 項）：一份有開花、有快開花、
/// 有練習、有一般考試跟詞彙考試、跨好幾天的資料，四頁（櫻花樹兩種畫法、紀錄頁全部／
/// 只看點亮）每個控制項點一次；沒資料也不會壞；390 寬不超出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);
  sakuraPetalsEnabled = false;

  /// あ行開過兩次花、か行考過還錯一個、さ行只練習；一般 50 音、詞彙考試；
  /// 今天、昨天、上個月都有。
  Future<MemoryStore> seed(WidgetTester tester) async {
    final store = MemoryStore();
    final now = DateTime.now();
    await tester.runAsync(() async {
      final exams = KanaExamRepository(store);
      final practice = KanaPracticeRepository(store);
      var n = 0;
      Future<void> round(
        String id,
        DateTime at,
        List<(String, String)> kana, {
        String? light,
        String type = 'kana',
        String wrong = '',
      }) async {
        var i = 0;
        for (final (k, r) in kana) {
          await exams.add(
            KanaExamEntry(
              id: '${n++}',
              roundId: id,
              kana: k,
              romaji: r,
              isCorrect: k != wrong,
              examType: type,
              savedAt: at.add(Duration(seconds: i++)),
              lightRow: light,
              writeMs: 2500,
              strokes: const [
                [(0.1, 0.1, 0.0), (0.4, 0.6, 50.0)],
              ],
            ),
          );
        }
      }

      final a = [...gojuonRows['あ']!, ...gojuonRowsKatakana['あ']!];
      final ka = [
        for (final r in ['あ', 'か']) ...[
          ...gojuonRows[r]!,
          ...gojuonRowsKatakana[r]!,
        ],
      ];
      await round('l1', now.subtract(const Duration(days: 35)), a, light: 'あ');
      await round('l2', now.subtract(const Duration(days: 1)), a, light: 'あ');
      await round(
        'l3',
        now.subtract(const Duration(hours: 2)),
        ka,
        light: 'か',
        wrong: 'キ',
      );
      await round(
        'k1',
        now.subtract(const Duration(hours: 1)),
        gojuonRows['さ']!,
      );
      await round(
        'v1',
        now.subtract(const Duration(minutes: 30)),
        const [('ねこ', '猫'), ('いぬ', '犬')],
        type: 'vocab',
        wrong: 'いぬ',
      );
      for (var i = 0; i < 6; i++) {
        final (k, r) = gojuonRows['さ']![i % 5];
        await practice.add(
          KanaPracticeEntry(
            id: 'p$i',
            kana: k,
            romaji: r,
            assisted: i.isEven,
            savedAt: now.subtract(Duration(days: i, minutes: 5)),
            strokes: const [
              [(0.2, 0.2, 0.0), (0.5, 0.5, 900.0)],
            ],
          ),
        );
      }
    });
    return store;
  }

  void quiet(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  final pages = <String, Widget Function()>{
    '日文首頁': () => const JpHomePage(),
    '日文統計': () => const JpStatsPage(),
    '練習紀錄（全部）': () => const JpLogPage(),
    '練習紀錄（只看點亮）': () => const JpLogPage(lightOnly: true),
    '櫻花樹（GPT 圖）': () => const JpLightPage(),
    '櫻花樹（開花慶祝）': () => const JpLightPage(celebrateRow: 'あ'),
  };

  for (final MapEntry(key: name, value: page) in pages.entries) {
    for (final empty in [false, true]) {
      testWidgets('$name${empty ? '（沒資料）' : ''}：每個控制項點一次', (tester) async {
        quiet(tester);
        final store = empty ? MemoryStore() : await seed(tester);
        final router = await pumpPage(
          tester,
          store,
          page,
          size: const Size(390, 860),
        );
        await settle(tester, 6);
        await tester.pump(const Duration(seconds: 3));
        await settle(tester, 2);
        await pokeAll(tester, router, max: 80, deep: true);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 6));
      });
    }
  }

  for (final ring in [true, false]) {
    testWidgets('櫻花樹（原本的畫法）、首頁${ring ? '顯示' : '不顯示'}進度環：每個控制項點一次', (
      tester,
    ) async {
      quiet(tester);
      final store = await seed(tester);
      for (final page in [
        () => const JpLightPage(),
        () => const JpHomePage(),
      ]) {
        final router = await pumpPage(
          tester,
          store,
          page,
          size: const Size(390, 860),
          overrides: [
            jpLightStyleProvider.overrideWith((ref) => JpLightStyle.classic),
            jpShowProgressRingProvider.overrideWith((ref) => ring),
          ],
        );
        await settle(tester, 6);
        await pokeAll(tester, router, max: 80, deep: true);
        expect(tester.takeException(), isNull);
      }
      await tester.pump(const Duration(seconds: 6));
    });
  }
}

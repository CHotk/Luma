import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/kana_exam_repository.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/features/kana_exam/kana_exam_history_page.dart';
import 'package:lume/features/kana_exam/kana_exam_page.dart';
import 'package:lume/features/kana_practice/kana_paper.dart';

import '../../support/poke.dart';

/// 50 音考試（2026-11-13 第 15 項）：
/// - 作答頁：沒下筆不能提交；提交後自評對／錯；「不會，看答案」沒下筆也能按；清除；
///   第二根手指不算；考完看結果（正確率、再考一次、返回）；詞彙模式；沒選範圍用固定
///   題庫；點亮模式錯一題就結束、全對開花、看櫻花樹。
/// - 紀錄頁：沒紀錄；50 音／點亮／詞彙篩選（含篩完沒有）；展開一輪；點一題重播（沒落筆的
///   也能點開）；長按改答對／答錯／刪除；清空（取消、確定）；匯出（切快照、下載、複製、關閉）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  void quiet(WidgetTester tester) {
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    addTearDown(
      () => m.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  Future<List<KanaExamEntry>> entries(
    WidgetTester tester,
    MemoryStore s,
  ) async => (await tester.runAsync(() => KanaExamRepository(s).loadAll()))!;

  Finder paper() => find
      .ancestor(
        of: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is InkPainter,
        ),
        matching: find.byType(Listener),
      )
      .first;

  Future<void> stroke(WidgetTester tester) async {
    final c = tester.getCenter(paper());
    final g = await tester.startGesture(c - const Offset(30, 30));
    await g.moveBy(const Offset(30, 30));
    await g.up();
    await tester.pump();
  }

  bool submitEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '提交'))
          .onPressed !=
      null;

  Future<void> tapText(WidgetTester tester, String t) async {
    await tester.tap(find.text(t).last);
    await settle(tester, 3);
  }

  /// 寫一筆、提交、自評。
  Future<void> answer(WidgetTester tester, {required bool right}) async {
    await stroke(tester);
    await tapText(tester, '提交');
    await tapText(tester, right ? '✓ 寫對了' : '✗ 寫錯了');
  }

  Future<void> unknown(WidgetTester tester) async {
    await tapText(tester, '不會，看答案');
    expect(find.text('公布答案'), findsOneWidget);
    await tapText(tester, '下一題');
  }

  GoRouter? lightRouter;
  Future<MemoryStore> openExam(WidgetTester tester, KanaExamPage page) async {
    quiet(tester);
    final store = MemoryStore();
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    lightRouter = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => page),
        GoRoute(
          path: '/jp-home',
          builder: (_, _) => const Scaffold(body: Text('日文首頁')),
        ),
        GoRoute(
          path: '/jp-light',
          builder: (_, s) => Scaffold(body: Text('櫻花樹:${s.extra}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(routerConfig: lightRouter),
      ),
    );
    await settle(tester, 2);
    return store;
  }

  testWidgets('50 音（あ行 5 題）：沒下筆不能提交、清除、對錯、不會；考完結果、再考一次', (tester) async {
    final store = await openExam(
      tester,
      const KanaExamPage(mode: ExamMode.kana, selectedRows: {'あ'}),
    );
    expect(find.text('1 / 5'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    await stroke(tester);
    expect(submitEnabled(tester), isTrue);
    // 清除：畫面上的筆畫跟提交鍵馬上跟著變。
    await tester.tap(find.text('清除'));
    await tester.pump();
    expect(submitEnabled(tester), isFalse);

    // 第二根手指不算。
    final c = tester.getCenter(paper());
    final a = await tester.startGesture(c, pointer: 5);
    final b = await tester.startGesture(c + const Offset(10, 0), pointer: 6);
    await b.moveBy(const Offset(5, 5));
    await b.up();
    await a.moveBy(const Offset(10, 10));
    await a.cancel();
    await tester.pump();

    await tapText(tester, '提交');
    expect(find.text('自己核對一下'), findsOneWidget);
    await tapText(tester, '✓ 寫對了');
    expect(find.text('2 / 5'), findsOneWidget);
    await answer(tester, right: false);
    await unknown(tester);
    await answer(tester, right: true);
    await answer(tester, right: true);
    await settle(tester, 4);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🌸 50 音考試完成！'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('3 / 5 題'), findsOneWidget);
    expect(find.text('多練幾次，肌肉記憶會自己長出來'), findsOneWidget);
    final all = await entries(tester, store);
    expect(all.length, 5);
    expect(all.where((e) => e.isCorrect).length, 3);
    expect(all.map((e) => e.roundId).toSet().length, 1);
    expect(all.where((e) => e.strokes.isEmpty).length, 1);

    await tapText(tester, '再考一次');
    expect(find.text('1 / 5'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await answer(tester, right: true);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('寫得很扎實，繼續保持'), findsOneWidget);
    final again = await entries(tester, store);
    expect(again.map((e) => e.roundId).toSet().length, 2);
    await tapText(tester, '返回模式選擇');
    expect(tester.takeException(), isNull);
  });

  testWidgets('詞彙考試 10 題全部不會；沒選範圍的 50 音是固定 20 題', (tester) async {
    final store = await openExam(
      tester,
      const KanaExamPage(mode: ExamMode.vocab),
    );
    expect(find.text('1 / 10'), findsOneWidget);
    expect(find.text('📝 詞彙考試'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await unknown(tester);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🌸 詞彙考試完成！'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect((await entries(tester, store)).first.examType, 'vocab');
    await tapText(tester, '再考一次');
    expect(find.text('1 / 10'), findsOneWidget);

    await openExam(tester, const KanaExamPage(mode: ExamMode.kana));
    expect(find.text('1 / 20'), findsOneWidget);
  });

  testWidgets('點亮あ行：錯一題就結束、看櫻花樹；再考一次全對開花', (tester) async {
    final store = await openExam(
      tester,
      const KanaExamPage(mode: ExamMode.kana, lightRow: 'あ'),
    );
    expect(find.text('1 / 10'), findsOneWidget);
    await answer(tester, right: true);
    await answer(tester, right: false);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('あ行 這次沒開花'), findsOneWidget);
    expect(find.textContaining('這次對了 1 題，錯在「'), findsOneWidget);
    expect(
      (await entries(tester, store)).every((e) => e.lightRow == 'あ'),
      isTrue,
    );

    await tapText(tester, '再考一次');
    for (var i = 0; i < 10; i++) {
      await answer(tester, right: true);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🌸 あ行 開花了！'), findsOneWidget);
    expect(find.text('這一行全對，櫻花樹上開了一朵'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    await tapText(tester, '🌸 看櫻花樹');
    // 疊在日文首頁上，帶著剛開花的那一行過去。
    expect(find.text('櫻花樹:あ'), findsOneWidget);
    expect(lightRouter!.canPop(), isTrue);
  });

  // ── 紀錄頁 ─────────────────────────────────────────────

  Future<MemoryStore> seed(WidgetTester tester) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final repo = KanaExamRepository(store);
      var n = 0;
      Future<void> add(
        String round,
        String type,
        String kana,
        bool ok, {
        String? light,
        bool strokes = true,
        double? ms,
      }) => repo.add(
        KanaExamEntry(
          id: '${n++}',
          roundId: round,
          kana: kana,
          romaji: 'x',
          isCorrect: ok,
          examType: type,
          savedAt: DateTime(2026, 10, 1, 8, n, n),
          lightRow: light,
          writeMs: ms,
          strokes: strokes
              ? const [
                  [(0.1, 0.1, 0.0), (0.5, 0.5, 40.0)],
                ]
              : const [],
        ),
      );
      await add('r1', 'kana', 'あ', true, ms: 70000);
      await add('r1', 'kana', 'い', false, strokes: false);
      await add('r2', 'kana', 'う', true, light: 'あ');
      await add('r3', 'vocab', 'ねこ', false, ms: 3000);
    });
    return store;
  }

  Future<void> openHistory(WidgetTester tester, MemoryStore store) async {
    quiet(tester);
    await pumpPage(
      tester,
      store,
      () => const KanaExamHistoryPage(),
      size: const Size(390, 1400),
    );
    await settle(tester, 4);
  }

  testWidgets('紀錄頁沒紀錄', (tester) async {
    await openHistory(tester, MemoryStore());
    expect(find.text('還沒有任何考試紀錄'), findsOneWidget);
  });

  testWidgets('紀錄頁：三種篩選、一輪的摘要（寫了幾分幾秒）、展開、重播、沒落筆的也能點開', (tester) async {
    await openHistory(tester, await seed(tester));
    expect(find.textContaining('這台瀏覽器'), findsOneWidget);
    expect(find.textContaining('正確率 50%（2 / 4 題）'), findsWidgets);
    expect(find.text('🌸 點亮 あ行'), findsOneWidget);
    expect(find.textContaining('寫了 1 分'), findsOneWidget);
    expect(find.textContaining('寫了 3 秒'), findsOneWidget);
    for (final (label, text) in [
      ('50 音', '正確率 50%（1 / 2 題）'),
      ('🌸 點亮', '正確率 100%（1 / 1 題）'),
      ('詞彙', '正確率 0%（0 / 1 題）'),
    ]) {
      await tester.tap(find.textContaining(label).first);
      await settle(tester, 2);
      expect(find.textContaining(text), findsWidgets, reason: label);
    }
    await tester.tap(find.textContaining('全部').first);
    await settle(tester, 2);

    // 展開 50 音那一輪，點有筆畫的那題重播。
    await tester.tap(find.text('50 音').last);
    await settle(tester, 2);
    await tester.tap(find.text('あ').first);
    await settle(tester, 3);
    expect(find.text('あ（x）'), findsOneWidget);
    await tester.tap(find.text('重播'));
    await tester.pump(const Duration(milliseconds: 300));
    await tapText(tester, '關閉');
    await tester.tap(find.text('い').first);
    await settle(tester, 3);
    expect(find.text('這題按了「不會」沒有落筆，沒有筆畫紀錄可以重播'), findsOneWidget);
    await tapText(tester, '關閉');
    // 收起來。
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await settle(tester, 2);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
  });

  testWidgets('紀錄頁：篩完沒有', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(
      () => KanaExamRepository(store).add(
        KanaExamEntry(
          id: '1',
          roundId: 'r',
          kana: 'あ',
          romaji: 'a',
          isCorrect: true,
          examType: 'kana',
          savedAt: DateTime(2026, 10, 1),
          strokes: const [],
        ),
      ),
    );
    await openHistory(tester, store);
    await tester.tap(find.textContaining('詞彙').first);
    await settle(tester, 2);
    expect(find.text('沒有符合篩選條件的紀錄'), findsOneWidget);
  });

  testWidgets('長按一題：改答錯、改答對、刪除；點旁邊不選', (tester) async {
    final store = await seed(tester);
    await openHistory(tester, store);
    await tester.tap(find.text('50 音').last);
    await settle(tester, 2);

    Future<void> menu(String kana, String? pick) async {
      // 存完重整後那一輪可能還開著，也可能收起來；沒開就打開。
      if (find.text(kana).evaluate().isEmpty) {
        await tester.tap(find.text('50 音').last);
        await settle(tester, 2);
      }
      await tester.longPress(find.text(kana).first);
      await settle(tester, 4);
      if (pick == null) {
        await tester.tapAt(const Offset(10, 1300));
      } else {
        await tester.tap(find.text(pick).last);
      }
      await settle(tester, 4);
    }

    bool? ok(List<KanaExamEntry> all, String kana) =>
        all.where((e) => e.kana == kana).firstOrNull?.isCorrect;

    await menu('あ', '答錯');
    expect(ok(await entries(tester, store), 'あ'), isFalse);
    await menu('い', '答對');
    expect(ok(await entries(tester, store), 'い'), isTrue);
    await menu('い', null);
    expect(ok(await entries(tester, store), 'い'), isTrue);
    await menu('い', '刪除');
    expect(ok(await entries(tester, store), 'い'), isNull);
  });

  testWidgets('清空：取消不動、確定全部清掉', (tester) async {
    final store = await seed(tester);
    await openHistory(tester, store);
    await tester.tap(find.byTooltip('清空紀錄'));
    await settle(tester, 3);
    await tapText(tester, '取消');
    expect((await entries(tester, store)).length, 4);
    await tester.tap(find.byTooltip('清空紀錄'));
    await settle(tester, 3);
    await tapText(tester, '清空');
    expect(await entries(tester, store), isEmpty);
    expect(find.text('已清空所有考試紀錄'), findsOneWidget);
    expect(find.text('還沒有任何考試紀錄'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
  });

  testWidgets('匯出：切快照、下載、複製、關閉', (tester) async {
    await openHistory(tester, await seed(tester));
    await tester.tap(find.byTooltip('匯出紀錄'));
    await settle(tester, 4);
    expect(find.textContaining('共 4 筆 ・'), findsOneWidget);
    await tester.tap(find.text('連考試紀錄快照一起'));
    await settle(tester, 4);
    await tester.tap(find.text('連考試紀錄快照一起'));
    await settle(tester, 2);
    await tester.tap(find.text('下載'));
    await settle(tester, 3);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await tester.tap(find.text('複製'));
    await settle(tester, 3);
    expect(find.text('已複製到剪貼簿'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await tester.tap(find.text('關閉'));
    await settle(tester, 2);
  });
}

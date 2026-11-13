import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/app/theme/colors.dart';
import 'package:lume/domain/models/word.dart';
import 'package:lume/domain/services/tts_service.dart';
import 'package:lume/shared/widgets/glass_card.dart';
import 'package:lume/shared/widgets/inline_text.dart';
import 'package:lume/shared/widgets/lume_mark.dart';
import 'package:lume/shared/widgets/ring_progress.dart';
import 'package:lume/shared/widgets/sakura_petals.dart';
import 'package:lume/shared/widgets/sense_tag.dart';
import 'package:lume/shared/widgets/settings_icon.dart';
import 'package:lume/shared/widgets/speaker_button.dart';
import 'package:lume/shared/widgets/stats_icon.dart';
import 'package:lume/shared/widgets/status_pill.dart';
import 'package:lume/shared/widgets/tag_badge.dart';
import 'package:lume/shared/widgets/trap_tag.dart';
import 'package:lume/shared/widgets/track_switcher.dart';

import '../support/poke.dart';

/// 共用小元件（2026-11-13 第 19 項）：進度環（沒題目、做一半、做滿變綠、超過）、
/// 粗體／程式碼行內文字（前後有字、沒有語法、只有語法）、狀態標籤三種、地雷字
/// 與義項標籤（能不能點、點了開筆記、未分類不顯示）、標籤徽章（空的不顯示）、
/// 發音鍵（英文、日文）、毛玻璃卡片與按鈕、Logo、櫻花飄落（關掉、開著跑一陣子
/// 花瓣出生又消失）、圖示讀不到退回內建圖示、語言切換膠囊。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> host(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  /// 帶路由的：點了會換頁的元件用，換到的頁面顯示路徑。
  Future<GoRouter> routed(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const [],
    String start = '/',
  }) async {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: Center(child: child)),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => Scaffold(body: Center(child: child)),
        ),
        GoRoute(
          path: '/jp-home',
          builder: (_, _) => Scaffold(body: Center(child: child)),
        ),
      ],
      errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          ...overrides,
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return router;
  }

  group('進度環', () {
    CustomPaint ringPaint(WidgetTester tester) => tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(RingProgress),
        matching: find.byType(CustomPaint),
      ),
    );

    for (final (name, done, total) in [
      ('沒題目', 0, 0),
      ('還沒開始', 0, 5),
      ('做一半', 2, 5),
      ('做滿', 5, 5),
      ('超過', 8, 5),
    ]) {
      testWidgets('$name（$done/$total）畫得出來', (tester) async {
        await host(
          tester,
          RingProgress(
            done: done,
            total: total,
            centerLabel: '$done/$total',
            bottomLabel: '3 分鐘',
            size: 120,
          ),
        );
        expect(find.text('$done/$total'), findsOneWidget);
        expect(find.text('今天的輪數'), findsOneWidget);
        expect(find.text('3 分鐘'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('進度或顏色變了才重畫', (tester) async {
      await host(
        tester,
        const RingProgress(
          done: 1,
          total: 5,
          centerLabel: 'a',
          bottomLabel: 'b',
        ),
      );
      final a = ringPaint(tester).painter!;
      await host(
        tester,
        const RingProgress(
          done: 1,
          total: 5,
          centerLabel: 'a',
          bottomLabel: 'b',
        ),
      );
      final same = ringPaint(tester).painter!;
      expect(same.shouldRepaint(a), isFalse);
      await host(
        tester,
        const RingProgress(
          done: 2,
          total: 5,
          centerLabel: 'a',
          bottomLabel: 'b',
        ),
      );
      expect(ringPaint(tester).painter!.shouldRepaint(a), isTrue);
      await host(
        tester,
        const RingProgress(
          done: 5,
          total: 5,
          centerLabel: 'a',
          bottomLabel: 'b',
        ),
      );
      final full = ringPaint(tester).painter!;
      await host(
        tester,
        const RingProgress(
          done: 9,
          total: 5,
          centerLabel: 'a',
          bottomLabel: 'b',
        ),
      );
      // 做滿跟超過：進度都是 1、都是綠色，不用重畫。
      expect(ringPaint(tester).painter!.shouldRepaint(full), isFalse);
    });
  });

  group('行內文字', () {
    List<InlineSpan> spans(WidgetTester tester) =>
        (tester.widget<RichText>(find.byType(RichText).first).text as TextSpan)
            .children!;

    testWidgets('粗體、程式碼、前後跟中間的一般字', (tester) async {
      await host(
        tester,
        const InlineText('前面**粗**中間`code`後面', style: TextStyle()),
      );
      final s = spans(tester).cast<TextSpan>();
      expect(s.map((e) => e.text), ['前面', '粗', '中間', 'code', '後面']);
      expect(s[1].style!.fontWeight, FontWeight.w700);
      expect(s[3].style!.fontFamily, 'Consolas');
      expect(s[3].style!.color, AppColors.accent);
    });

    testWidgets('沒有語法就是一整段；只有語法沒有前後字；沒配對的星號照原樣', (tester) async {
      await host(tester, const InlineText('一般的字', style: TextStyle()));
      expect(spans(tester).cast<TextSpan>().map((e) => e.text), ['一般的字']);
      await host(tester, const InlineText('**全粗**', style: TextStyle()));
      expect(spans(tester).cast<TextSpan>().map((e) => e.text), ['全粗']);
      await host(tester, const InlineText('**沒配對', style: TextStyle()));
      expect(spans(tester).cast<TextSpan>().map((e) => e.text), ['**沒配對']);
      await host(tester, const InlineText('', style: TextStyle()));
      expect(spans(tester), isEmpty);
    });
  });

  testWidgets('狀態標籤：三種狀態各自的字跟顏色', (tester) async {
    for (final (s, color) in [
      (WordStatus.confirmed, AppColors.statusMastered),
      (WordStatus.pending, AppColors.statusPending),
      (WordStatus.untested, AppColors.statusUntested),
    ]) {
      await host(tester, StatusPill(status: s));
      final t = tester.widget<Text>(find.text(s.label));
      expect(t.style!.color, color);
    }
  });

  testWidgets('地雷字：清單上不給點；詳情頁給點，點了開那則筆記', (tester) async {
    await routed(tester, const TrapTag(noteNo: '3'));
    expect(find.text('地雷字'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
    await routed(tester, const TrapTag(noteNo: '3', tappable: true));
    await tester.tap(find.text('地雷字 · 看說明'));
    await tester.pumpAndSettle();
    expect(find.text('route:/notes/traps/3'), findsOneWidget);
  });

  testWidgets('義項標籤：未分類不顯示；沒筆記或清單上不給點；能點就開義項筆記', (tester) async {
    await routed(tester, const SenseTag(senseCount: WordSenseCount.none));
    expect(find.byType(Text), findsNothing);
    await routed(
      tester,
      const SenseTag(senseCount: WordSenseCount.few, tappable: true),
    );
    expect(find.text('多義'), findsOneWidget);
    await routed(
      tester,
      const SenseTag(senseCount: WordSenseCount.many, noteNo: '5'),
    );
    expect(find.text('極多義'), findsOneWidget);
    await routed(
      tester,
      const SenseTag(
        senseCount: WordSenseCount.single,
        noteNo: '5',
        tappable: true,
      ),
    );
    await tester.tap(find.text('單義 · 看義項'));
    await tester.pumpAndSettle();
    expect(find.text('route:/notes/senses/5'), findsOneWidget);
  });

  testWidgets('標籤徽章：沒標籤不顯示；好幾個用頓號接起來', (tester) async {
    await host(tester, const TagBadge(tags: []));
    expect(find.byType(Text), findsNothing);
    await host(tester, const TagBadge(tags: ['食物', '水果']));
    expect(find.text('食物、水果'), findsOneWidget);
  });

  testWidgets('發音鍵：點了用 TTS 唸，日文要帶 japanese', (tester) async {
    final tts = _FakeTts();
    await routed(
      tester,
      const Column(
        children: [
          SpeakerButton(text: 'apple'),
          SpeakerButton(text: 'あ', japanese: true, size: 30),
        ],
      ),
      overrides: [ttsServiceProvider.overrideWith((ref) async => tts)],
    );
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton).last);
    await tester.pumpAndSettle();
    expect(tts.spoken, ['apple:false', 'あ:true']);
    expect(find.byTooltip('播放發音'), findsNWidgets(2));
  });

  testWidgets('毛玻璃卡片（能點、不能點）、主要按鈕、小標、Logo', (tester) async {
    var taps = 0;
    var presses = 0;
    await host(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlassCard(child: Text('不能點')),
          GlassCard(onTap: () => taps++, child: const Text('能點')),
          SizedBox(
            width: 200,
            child: GlassButton(label: '開始', onPressed: () => presses++),
          ),
          const PanelLabel('TODAY'),
          const LumeMark(size: 48),
        ],
      ),
    );
    await tester.tap(find.text('不能點'));
    await tester.tap(find.text('能點'));
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(taps, 1);
    expect(presses, 1);
    expect(find.text('TODAY'), findsOneWidget);
    final mark = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(LumeMark),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(mark.painter!.shouldRepaint(mark.painter!), isFalse);
    expect(tester.takeException(), isNull);
  });

  group('櫻花飄落', () {
    tearDown(() => sakuraPetalsEnabled = false);

    testWidgets('關掉時只有內容、不畫花瓣', (tester) async {
      sakuraPetalsEnabled = false;
      await host(tester, const SakuraPetals(child: Text('內容')));
      expect(find.text('內容'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SakuraPetals),
          matching: find.byType(IgnorePointer),
        ),
        findsNothing,
      );
    });

    testWidgets('開著跑兩分鐘：花瓣一片片出生、飄完消失，點擊穿透到底下', (tester) async {
      sakuraPetalsEnabled = true;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SakuraPetals(
              child: Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('底下的按鈕'),
                ),
              ),
            ),
          ),
        ),
      );
      final paint = find.descendant(
        of: find.byType(SakuraPetals),
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsWidgets);
      // 一格 200ms 跑兩分鐘：中間會出生好幾片（含偶爾連兩片）、也會有飄完被清掉的。
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(find.text('底下的按鈕'));
      await tester.pump();
      expect(taps, 1);
      final painter = tester.widget<CustomPaint>(paint.last).painter!;
      expect(painter.shouldRepaint(painter), isTrue);
      expect(tester.takeException(), isNull);
      // 拆掉時 ticker 跟著收掉，不會漏。
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('統計、設定圖示：讀得到用圖；讀不到退回內建圖示', (tester) async {
    await host(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatsIcon(),
          SettingsIcon(size: 24, color: Colors.red),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _BrokenBundle(),
        child: const MaterialApp(
          home: Scaffold(body: Row(children: [StatsIcon(), SettingsIcon()])),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('語言切換膠囊：點目前那邊不動；點另一邊存最後的語言、換到那個首頁', (tester) async {
    final store = MemoryStore();
    final router = await routed(
      tester,
      const TrackSwitcher(current: LearningTrack.en),
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
      start: '/home',
    );
    await tester.tap(find.text('英文'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    await tester.tap(find.text('日文'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/jp-home');
    expect(store.data.values.any((v) => v.contains('ja')), isTrue);
  });
}

class _FakeTts implements TtsService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text, {bool japanese = false}) async =>
      spoken.add('$text:$japanese');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 每張圖都讀不到的資產包（測圖示退回內建圖示）。
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.png')) throw FlutterError('沒有這張圖：$key');
    return rootBundle.load(key);
  }
}

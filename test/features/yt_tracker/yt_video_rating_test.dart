import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_crypto_stats_page.dart';
import 'package:lume/features/yt_tracker/yt_rating_ui.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

/// 幣圈影片準度評價（2026-11-11，設計稿最終版）。
void main() {
  final t0 = DateTime(2026, 11, 1);
  YtVideoRating r(YtVerdict? v, {String ch = 'c1', DateTime? due}) =>
      YtVideoRating(at: t0, verdict: v, channelId: ch, dueAt: due);

  test('命中率＝(對＋半對×0.5)÷已評；沒給方向不算；少於 3 部是資料少', () {
    final a = ytAccuracyOf([
      r(YtVerdict.ok),
      r(YtVerdict.ok),
      r(YtVerdict.half),
      r(YtVerdict.bad),
      r(YtVerdict.none),
      r(null, due: DateTime(2026, 12, 1)),
      r(YtVerdict.ok, ch: 'other'),
    ], channelId: 'c1');
    expect(a.rated, 4);
    expect(a.none, 1);
    expect(a.pending, 1);
    expect(a.rate, (2 + 0.5) / 4 * 100);
    expect(a.grade, 'B'); // 62.5
    expect(a.label, 'B 63%');
    final few = ytAccuracyOf([r(YtVerdict.ok), r(YtVerdict.ok)]);
    expect(few.enough, isFalse);
    expect(few.grade, isNull);
    expect(few.label, '資料少');
    expect(
      ytAccuracyOf([for (var i = 0; i < 4; i++) r(YtVerdict.ok)]).grade,
      'S',
    );
  });

  test('存檔來回、同步合併後改的贏（清掉的墓碑也會蓋過去）', () {
    final full = YtVideoRating(
      at: t0,
      verdict: YtVerdict.half,
      claim: 'BTC 站上 8 萬',
      dueAt: DateTime(2026, 11, 15),
      note: '差一點',
      channelId: 'c1',
      channelName: '幣圈頻道',
      title: '影片',
      ratedAt: t0,
    );
    final back = YtVideoRatingStore.decode(
      YtVideoRatingStore.encode({'v': full}),
    )['v']!;
    expect(back.verdict, YtVerdict.half);
    expect(back.claim, 'BTC 站上 8 萬');
    expect(back.dueAt, DateTime(2026, 11, 15));
    expect(back.channelName, '幣圈頻道');
    final tomb = YtVideoRating(at: t0.add(const Duration(days: 1)));
    final m = YtVideoRatingStore.merge({'v': full}, {'v': tomb});
    expect(m['v']!.isEmpty, isTrue);
    final m2 = YtVideoRatingStore.merge({'v': tomb}, {'v': full});
    expect(m2['v']!.isEmpty, isTrue, reason: '比較舊的不會蓋過新的');
  });

  Future<(_MemoryStore, ProviderContainer)> pump(
    WidgetTester tester, {
    required bool crypto,
  }) async {
    final store = _MemoryStore();
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                YtVideoRow(
                  video: YoutubeVideo(
                    videoId: 'v1',
                    title: 'BTC 下週看漲',
                    publishedAt: DateTime(2026, 1, 1),
                    thumbnailUrl: '',
                  ),
                  subtitle: '',
                  channelId: 'c1',
                  channelName: '幣圈頻道',
                  cryptoMode: crypto,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (store, container);
  }

  Future<void> swipe(WidgetTester tester) async {
    await tester.timedDrag(
      find.text('BTC 下週看漲'),
      const Offset(-320, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('幣圈：往左滑有 對／不對／沒方向／預測，按「對」記下來、縮圖左下有標籤，再按一次取消', (tester) async {
    final (store, container) = await pump(tester, crypto: true);
    await swipe(tester);
    for (final t in ['對', '不對', '沒方向', '預測', '隱藏']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('對'));
    await tester.pumpAndSettle();
    final saved = container.read(ytVideoRatingsProvider)['v1']!;
    expect(saved.verdict, YtVerdict.ok);
    expect(saved.channelId, 'c1');
    expect(saved.title, 'BTC 下週看漲');
    expect(
      (await YtVideoRatingStore(store).load())['v1']!.verdict,
      YtVerdict.ok,
    );
    expect(find.text('○ 對'), findsOneWidget); // 縮圖左下角
    await swipe(tester);
    await tester.tap(find.text('對'));
    await tester.pumpAndSettle();
    expect(container.read(ytVideoRatingsProvider)['v1'], isNull);
    expect(find.text('○ 對'), findsNothing);
  });

  testWidgets('幣圈：記預測 → 待驗證，列上直接有「說對／說錯」可以驗證', (tester) async {
    final (_, container) = await pump(tester, crypto: true);
    await swipe(tester);
    await tester.tap(find.text('預測'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('predict_claim')),
      'BTC 兩週內站上 8 萬',
    );
    await tester.tap(find.byKey(const ValueKey('predict_days_7')));
    await tester.tap(find.byKey(const ValueKey('predict_ok')));
    await tester.pumpAndSettle();
    final p = container.read(ytVideoRatingsProvider)['v1']!;
    expect(p.pending, isTrue);
    expect(p.claim, 'BTC 兩週內站上 8 萬');
    expect(find.textContaining('天後驗證'), findsOneWidget);
    expect(find.text('預測：BTC 兩週內站上 8 萬'), findsOneWidget);
    await tester.tap(find.text('✕ 說錯'));
    await tester.pumpAndSettle();
    final v = container.read(ytVideoRatingsProvider)['v1']!;
    expect(v.verdict, YtVerdict.bad);
    expect(v.claim, 'BTC 兩週內站上 8 萬', reason: '預測內容留著');
    expect(find.text('✕ 不對'), findsOneWidget);
  });

  testWidgets('幣圈：⋮ 是居中視窗、上面有四種評價，沒有「加到音樂功能」', (tester) async {
    final (_, container) = await pump(tester, crypto: true);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('加到音樂功能'), findsNothing);
    for (final v in YtVerdict.values) {
      expect(find.byKey(ValueKey('menu_verdict_${v.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('menu_verdict_none')));
    await tester.pumpAndSettle();
    expect(
      container.read(ytVideoRatingsProvider)['v1']!.verdict,
      YtVerdict.none,
    );
    expect(find.text('— 沒給方向'), findsOneWidget);
  });

  testWidgets('不是幣圈：沒有評價鈕、⋮ 照舊是底部選單有「加到音樂功能」', (tester) async {
    await pump(tester, crypto: false);
    await swipe(tester);
    expect(find.text('不對'), findsNothing);
    expect(find.text('紀錄'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('加到音樂功能'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('準度統計頁：整體命中率、頻道排行（至少幾部）、點頻道看依評價篩影片', (tester) async {
    final store = _MemoryStore();
    final ratings = {
      for (var i = 0; i < 4; i++)
        'a$i': YtVideoRating(
          at: t0,
          verdict: i < 3 ? YtVerdict.ok : YtVerdict.bad,
          channelId: 'A',
          channelName: '準頻道',
          title: 'A 影片 $i',
          ratedAt: t0,
        ),
      'b0': YtVideoRating(
        at: t0,
        verdict: YtVerdict.bad,
        channelId: 'B',
        channelName: '少頻道',
        title: 'B 影片',
        ratedAt: t0,
      ),
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          ytVideoRatingsProvider.overrideWith((ref) => ratings),
        ],
        child: const MaterialApp(home: YtCryptoStatsPage()),
      ),
    );
    await tester.pumpAndSettle();
    // 整體：對 3、不對 2 → 60%。
    expect(find.text('60%'), findsOneWidget);
    // 預設至少 3 部：「少頻道」只評 1 部，先藏起來。
    expect(find.byKey(const ValueKey('rank_A')), findsOneWidget);
    expect(find.byKey(const ValueKey('rank_B')), findsNothing);
    expect(find.textContaining('另外 1 個頻道'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('min_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rank_B')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rank_A')));
    await tester.pumpAndSettle();
    expect(find.text('準頻道・準度'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '✕ 不對').last);
    await tester.pumpAndSettle();
    expect(find.text('A 影片 3'), findsOneWidget);
    expect(find.text('A 影片 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('分類名有「幣圈」才算幣圈分類', () {
    expect(isCryptoCategoryName('幣圈'), isTrue);
    expect(isCryptoCategoryName('幣圈 KOL'), isTrue);
    expect(isCryptoCategoryName('音樂'), isFalse);
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

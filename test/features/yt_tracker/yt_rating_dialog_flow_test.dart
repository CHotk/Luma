import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/features/yt_tracker/yt_rating_ui.dart';

import '../../support/poke.dart';

/// 幣圈評價視窗的每條路（2026-11-12 補到 95%）：評價帶備註、再評一次不會取消、
/// 記預測（選天數、取消不記）、有預測時顯示預測、清除、關閉不動；篩選比對、顏色、圖示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final video = YoutubeVideo(
    videoId: 'v1',
    title: 'BTC 會漲嗎',
    publishedAt: DateTime(2026, 11, 1),
    thumbnailUrl: '',
  );

  late WidgetRef hostRef;
  late BuildContext hostCtx;

  Future<MemoryStore> host(WidgetTester tester) async {
    final store = MemoryStore();
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, ref, _) {
                hostRef = ref;
                hostCtx = c;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
    return store;
  }

  YtVideoRating? now() => hostRef.read(ytVideoRatingsProvider)['v1'];

  Future<void> open(WidgetTester tester, {String ch = 'a'}) async {
    showYtRatingDialog(
      hostCtx,
      hostRef,
      video: video,
      channelId: ch,
      channelName: ch.isEmpty ? '' : '頻道$ch',
    );
    await settle(tester, 3);
  }

  testWidgets('評價帶備註、再評同一個不會取消、清除、關閉不動', (tester) async {
    final store = await host(tester);
    await open(tester);
    expect(find.text('清除'), findsNothing);
    await tester.enterText(find.byType(TextField), '  講得很準  ');
    await tester.tap(find.byKey(const ValueKey('verdict_ok')));
    await settle(tester);
    expect(now()!.verdict, YtVerdict.ok);
    expect(now()!.note, '講得很準');
    expect(now()!.channelName, '頻道a');

    // 再開：選中的那個亮著，同一個再按一次還是 ok（視窗裡不切換）。
    await open(tester);
    expect(find.text('講得很準'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('verdict_ok')));
    await settle(tester);
    expect(now()!.verdict, YtVerdict.ok);

    await open(tester);
    await tester.tap(find.text('關閉'));
    await settle(tester);
    expect(now()!.verdict, YtVerdict.ok);

    await open(tester);
    await tester.tap(find.text('清除'));
    await settle(tester);
    expect(now(), isNull);
    final saved = await tester.runAsync(
      () => YtVideoRatingStore(store).loadAll(),
    );
    // 存檔留墓碑（別台同步也會清掉）。
    expect(saved!['v1']!.isEmpty, isTrue);
  });

  testWidgets('記預測：選天數記下來、清掉原本評價；有預測時視窗顯示；取消不記', (tester) async {
    await host(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('verdict_bad')));
    await settle(tester);
    expect(now()!.verdict, YtVerdict.bad);

    await open(tester);
    await tester.tap(find.text('記預測'));
    await settle(tester, 3);
    expect(find.text('記下他的預測'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('predict_claim')),
      ' BTC 站上 8 萬 ',
    );
    await tester.tap(find.byKey(const ValueKey('predict_days_3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('predict_ok')));
    await settle(tester);
    expect(now()!.claim, 'BTC 站上 8 萬');
    expect(now()!.verdict, isNull);
    expect(now()!.pending, isTrue);
    final due = now()!.dueAt!;
    final d = DateTime.now().add(const Duration(days: 3));
    expect(due, DateTime(d.year, d.month, d.day));

    await open(tester);
    expect(find.text('預測：BTC 站上 8 萬'), findsOneWidget);
    await tester.tap(find.text('記預測'));
    await settle(tester, 3);
    // 帶原本的預測。
    expect(find.text('BTC 站上 8 萬'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('predict_claim')), '改掉');
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(now()!.claim, 'BTC 站上 8 萬');
  });

  testWidgets('沒頻道 id／名字的影片也能評；沒評過按清除路徑不存在', (tester) async {
    await host(tester);
    await tester.runAsync(() => YtRatingActions(hostRef).clear(video));
    expect(now(), isNull);
    await open(tester, ch: '');
    await tester.tap(find.byKey(const ValueKey('verdict_none')));
    await settle(tester);
    expect(now()!.verdict, YtVerdict.none);
    expect(now()!.channelId ?? '', isEmpty);
    // 列表上的快速評價：同一個再按一次取消。
    await tester.runAsync(
      () => YtRatingActions(hostRef).rate(video, '', '', YtVerdict.none),
    );
    expect(now()?.verdict, isNull);
  });

  test('篩選比對、顏色、圖示、幣圈分類名', () {
    final r = YtVideoRating(at: DateTime(2026), verdict: YtVerdict.half);
    expect(ytRatingMatches(null, 'half'), isFalse);
    expect(ytRatingMatches(r, 'half'), isTrue);
    expect(ytRatingMatches(r, 'ok'), isFalse);
    expect(ytRatingMatches(r, 'pending'), r.pending);
    final p = YtVideoRating(
      at: DateTime(2026),
      claim: '會漲',
      dueAt: DateTime(2026, 1, 2),
    );
    expect(ytRatingMatches(p, 'pending'), isTrue);
    for (final v in YtVerdict.values) {
      expect(ytVerdictColor(v), isNotNull);
      expect(ytVerdictIcon(v), isNotNull);
    }
    expect(isCryptoCategoryName('我的幣圈'), isTrue);
    expect(isCryptoCategoryName('投資'), isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_embed_player_style_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/repositories/yt_video_open_mode_store.dart';
import 'package:lume/data/repositories/yt_video_hidden_store.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/repositories/yt_video_watch_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_floating_player.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

import '../../support/poke.dart';

/// 影片列（2026-11-12 補到 95%）：點開（已下架、內嵌三種呈現、開外部連結）、
/// ⋮ 選單每一項（歌曲、加到音樂、播放清單、移到最上面、移除＋復原、紀錄、隱藏／
/// 取消隱藏、在 YouTube 開）、幣圈選單（四種評價、記預測、備註、清除）、往左滑的按鈕。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  YoutubeVideo video({DateTime? removed}) => YoutubeVideo(
    videoId: 'v1',
    title: '測試影片',
    publishedAt: DateTime.now().subtract(const Duration(days: 2)),
    thumbnailUrl: '',
    duration: const Duration(minutes: 12),
    viewCount: 12345,
    removedAt: removed,
  );

  late ProviderContainer container;
  String? copied;

  Future<MemoryStore> pump(
    WidgetTester tester, {
    YoutubeVideo? v,
    bool crypto = false,
    bool song = false,
    String? playlistId,
    YtVideoOpenMode mode = YtVideoOpenMode.external,
    YtEmbedPlayerStyle style = YtEmbedPlayerStyle.floating,
    MemoryStore? store,
  }) async {
    copied = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final s = store ?? MemoryStore();
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(s),
          ytVideoOpenModeProvider.overrideWith((_) => mode),
          ytEmbedPlayerStyleProvider.overrideWith((_) => style),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                YtVideoRow(
                  video: v ?? video(),
                  subtitle: '頻道a・2 天前',
                  channelId: 'a',
                  channelName: '頻道a',
                  playlistId: playlistId,
                  songMode: song,
                  cryptoMode: crypto,
                  highlight: '影片',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(YtVideoRow)),
    );
    await settle(tester, 2);
    return s;
  }

  Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await settle(tester, 3);
    // 往左滑的按鈕也有一樣的字，只點選單裡那個。
    await tester.tap(
      find.descendant(of: find.byType(ListTile), matching: find.text(item)),
    );
    await settle(tester, 4);
  }

  Future<void> endNotices(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 3);
  }

  testWidgets('點開：已下架的說一聲、不開', (tester) async {
    await pump(tester, v: video(removed: DateTime(2026, 10, 12)));
    expect(find.text('已下架'), findsOneWidget);
    await tester.tap(find.text('測試影片'));
    await settle(tester, 2);
    expect(find.text('這部影片已經下架'), findsOneWidget);
    expect(find.textContaining('10/12 發現'), findsOneWidget);
    await endNotices(tester);
  });

  testWidgets('點開：外部連結（這個平台開不了→複製網址），記一筆已看過', (tester) async {
    final store = await pump(tester);
    await tester.tap(find.text('測試影片'));
    await settle(tester, 3);
    expect(copied, contains('v1'));
    final rec = await tester.runAsync(() => YtVideoWatchStore(store).loadAll());
    expect(rec!['v1'], isNotNull);
    await endNotices(tester);
  });

  for (final style in YtEmbedPlayerStyle.values) {
    testWidgets('點開：內嵌播放（${style.name}）、關掉', (tester) async {
      await pump(tester, mode: YtVideoOpenMode.embedded, style: style);
      await tester.tap(find.text('測試影片'));
      await settle(tester, 4);
      expect(find.text('這個平台不支援內嵌播放'), findsOneWidget);
      if (style == YtEmbedPlayerStyle.floating) {
        YtFloatingPlayer.close();
      } else {
        await tester.tap(find.byTooltip('在 YouTube 開啟'));
        await settle(tester, 2);
        expect(copied, contains('v1'));
        await tester.tap(find.byTooltip('關閉'));
      }
      await settle(tester, 3);
      expect(find.text('這個平台不支援內嵌播放'), findsNothing);
      await endNotices(tester);
    });
  }

  testWidgets('選單：標成歌曲／取消、紀錄（沒紀錄）、隱藏／取消隱藏、在 YouTube 開', (tester) async {
    final store = await pump(tester, song: true);
    await menu(tester, '標成歌曲');
    expect(container.read(ytVideoSongsProvider), contains('v1'));
    await menu(tester, '取消歌曲');
    expect(container.read(ytVideoSongsProvider), isNot(contains('v1')));
    await menu(tester, '開啟紀錄');
    expect(find.text('這支影片還沒有開啟紀錄'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await settle(tester, 2);
    await menu(tester, '隱藏這部');
    expect(
      await tester.runAsync(() => YtVideoHiddenStore(store).contains('v1')),
      isTrue,
    );
    // 沒強制顯示：隱藏了就不見。
    expect(find.text('測試影片'), findsNothing);
  });

  testWidgets('隱藏過的（強制顯示）：取消隱藏；在 YouTube 開', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(() => YtVideoHiddenStore(store).hide('v1'));
    copied = null;
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                YtVideoRow(
                  video: video(),
                  subtitle: 's',
                  channelId: 'a',
                  channelName: '頻道a',
                  forceShow: true,
                  fromCache: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester, 3);
    await menu(tester, '取消隱藏');
    expect(
      await tester.runAsync(() => YtVideoHiddenStore(store).contains('v1')),
      isFalse,
    );
    await menu(tester, '在 YouTube 開啟');
    expect(copied, contains('v1'));
    await endNotices(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('選單：開啟紀錄（超過 50 筆只列 50）', (tester) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final w = YtVideoWatchStore(store);
      for (var i = 0; i < 53; i++) {
        await w.markOpened('v1', channelId: 'a');
      }
    });
    await pump(tester, store: store);
    await menu(tester, '開啟紀錄');
    expect(find.text('還有 3 筆沒列出來'), findsOneWidget);
  });

  testWidgets('在播放清單裡：添加到播放清單、移到最上面、移除＋復原', (tester) async {
    final store = MemoryStore();
    final now = DateTime.now();
    YtPlaylistItem it(String id) => YtPlaylistItem(
      video: YoutubeVideo(
        videoId: id,
        title: id,
        publishedAt: now,
        thumbnailUrl: '',
      ),
      channelName: '頻道a',
      addedAt: now,
    );
    await pump(tester, playlistId: YtPlaylist.laterId, store: store);
    container.read(ytPlaylistsProvider.notifier).state = [
      YtPlaylist.emptyLater().copyWith(items: [it('x'), it('v1')]),
    ];
    await settle(tester, 2);
    List<String> ids() => container
        .read(ytPlaylistsProvider)
        .first
        .items
        .map((i) => i.videoId)
        .toList();
    await menu(tester, '移到最上面');
    expect(ids(), ['v1', 'x']);
    await menu(tester, '從「稍後觀看」移除');
    expect(ids(), ['x']);
    await tester.pump(const Duration(milliseconds: 400));
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, '復原'))
        .onPressed!();
    await settle(tester, 3);
    expect(ids(), ['v1', 'x']);
    await endNotices(tester);
    await menu(tester, '添加到播放清單');
    expect(find.text('添加到播放清單'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await settle(tester, 3);
    final saved = await tester.runAsync(() => YtPlaylistStore(store).loadAll());
    expect(saved, isNotEmpty);
  });

  testWidgets('選單：加到音樂功能（打開表單再關掉）', (tester) async {
    await pump(tester);
    await menu(tester, '加到音樂功能');
    expect(tester.takeException(), isNull);
    await closeOverlays(tester);
  });

  testWidgets('幣圈選單：四種評價、記預測取消、評價備註關閉、清除評價', (tester) async {
    await pump(tester, crypto: true);
    YtVideoRating? r() => container.read(ytVideoRatingsProvider)['v1'];
    for (final v in YtVerdict.values) {
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester, 3);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text(v.label)),
      );
      await settle(tester, 3);
      expect(r()!.verdict, v);
    }
    await menu(tester, '記預測（等行情走完再驗證）');
    expect(find.text('記下他的預測'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    await menu(tester, '評價備註…');
    expect(find.text('這部影片說得準嗎？'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await settle(tester, 3);
    await menu(tester, '清除評價');
    expect(r(), isNull);
  });

  testWidgets('幣圈：預測完整顯示，驗證前後都看得到（2026-11-13）', (tester) async {
    await pump(tester, crypto: true);
    final long = List.filled(8, '比特幣兩週內站上八萬然後回測').join('，');
    container.read(ytVideoRatingsProvider.notifier).state = {
      'v1': YtVideoRating(
        at: DateTime.now(),
        claim: long,
        dueAt: DateTime.now().add(const Duration(days: 3)),
      ),
    };
    await settle(tester, 2);
    Text claim() => tester.widget<Text>(find.text('預測：$long'));
    expect(claim().maxLines, isNull);
    expect(claim().overflow, isNull);
    container.read(ytVideoRatingsProvider.notifier).state = {
      'v1': YtVideoRating(
        at: DateTime.now(),
        claim: long,
        verdict: YtVerdict.ok,
        ratedAt: DateTime.now(),
        note: '準',
      ),
    };
    await settle(tester, 2);
    expect(claim().maxLines, isNull);
    expect(find.text('備註：準'), findsOneWidget);
  });

  Future<void> swipeOpen(WidgetTester tester) async {
    await tester.drag(find.text('測試影片'), const Offset(-260, 0));
    await settle(tester, 3);
  }

  testWidgets('往左滑：紀錄、隱藏；拉開後點一下收起；往右甩收起', (tester) async {
    await pump(tester);
    await swipeOpen(tester);
    await tester.tap(find.text('紀錄'));
    await settle(tester, 3);
    expect(find.text('開啟紀錄'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await settle(tester, 3);
    await swipeOpen(tester);
    // 拉開時點影片是收起來，不是開影片。
    await tester.tap(find.text('測試影片'), warnIfMissed: false);
    await settle(tester, 3);
    expect(copied, isNull);
    await swipeOpen(tester);
    await tester.fling(find.text('測試影片'), const Offset(200, 0), 1500);
    await settle(tester, 3);
    // 輕輕甩一下往左也會打開。
    await tester.fling(find.text('測試影片'), const Offset(-30, 0), 1500);
    await settle(tester, 3);
    await tester.tap(find.text('隱藏'));
    await settle(tester, 3);
    expect(find.text('測試影片'), findsNothing);
  });

  testWidgets('幣圈往左滑：對、不對、沒方向、預測', (tester) async {
    await pump(tester, crypto: true);
    for (final label in ['對', '不對', '沒方向']) {
      await swipeOpen(tester);
      await tester.tap(find.text(label).last);
      await settle(tester, 3);
    }
    expect(
      container.read(ytVideoRatingsProvider)['v1']!.verdict,
      YtVerdict.none,
    );
    await swipeOpen(tester);
    await tester.tap(find.text('預測'));
    await settle(tester, 3);
    expect(find.text('記下他的預測'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
  });
}

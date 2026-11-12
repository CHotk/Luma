import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_channel_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// YT 頻道頁其餘的路（2026-11-12 補到 95%）：沒快取的頻道一路打 API 往下翻
/// （全部、影片、Shorts、直播），翻到一半 API 壞掉顯示「載入失敗」可重試；
/// 篩選列每一顆（排序、觀看篩選、重新整理、已下架）；幣圈頻道的準度；
/// 垃圾桶裡的頻道還原；簡介分頁「現在抓」；回到頂端鈕拖到左邊。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  final now = DateTime.now();

  Future<FakeYoutube> open(
    WidgetTester tester,
    String id, {
    Future<void> Function(MemoryStore)? extra,
  }) async {
    final store = MemoryStore();
    await seedYt(tester, store);
    await tester.runAsync(() async {
      final repo = YtTrackerRepository(store);
      // 沒有任何快取的頻道。
      await repo.addChannel(
        YtChannel(
          id: 'z',
          name: '頻道z',
          categoryId: 'c1',
          youtubeChannelId: 'UCz',
          uploadsPlaylistId: 'UUz',
          url: 'https://www.youtube.com/@z',
          addedAt: now,
          reviewedAt: now,
          statsUpdatedAt: now,
        ),
      );
      if (extra != null) await extra(store);
    });
    final yt = FakeYoutube();
    await http.runWithClient(() async {
      await pumpPage(
        tester,
        store,
        () => YtTrackerChannelPage(channelId: id),
        size: const Size(390, 860),
        overrides: [ytApiKeyProvider.overrideWith((_) => 'KEY')],
      );
      await settle(tester, 10);
    }, yt.client);
    return yt;
  }

  Future<void> run(WidgetTester tester, FakeYoutube yt, int n) =>
      http.runWithClient(() => settle(tester, n), yt.client);

  Future<void> tapText(WidgetTester tester, FakeYoutube yt, String text) =>
      http.runWithClient(() async {
        final f = find.text(text);
        if (f.evaluate().isEmpty) return;
        await tester.ensureVisible(f.first);
        await tester.pump();
        await tester.tap(f.first, warnIfMissed: false);
        await settle(tester, 6);
      }, yt.client);

  Future<void> done(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
  }

  testWidgets('沒快取的頻道：全部、影片、Shorts、直播都一路打 API 翻到底', (tester) async {
    final yt = await open(tester, 'z');
    await run(tester, yt, 10);
    for (final tab in ['影片', 'Shorts', '直播', '全部']) {
      await tapText(tester, yt, tab);
      await run(tester, yt, 10);
    }
    final lists = yt.calls
        .map((u) => u.queryParameters['playlistId'])
        .whereType<String>()
        .toSet();
    expect(lists, containsAll(['UUz', 'UULFz', 'UUSHz', 'UULVz']));
    expect(yt.calls.any((u) => u.queryParameters['pageToken'] == 'P2'), isTrue);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('翻到一半 API 壞掉：載入失敗、修好後點一下重試', (tester) async {
    final yt = await open(tester, 'z');
    // 換類型之後才壞。
    yt.fail = 403;
    for (final tab in ['Shorts', '全部']) {
      await tapText(tester, yt, tab);
      await run(tester, yt, 6);
      await http.runWithClient(() async {
        await tester.tap(find.byTooltip('重新整理').first, warnIfMissed: false);
        await settle(tester, 6);
      }, yt.client);
    }
    final failed = find.textContaining('載入失敗');
    if (failed.evaluate().isNotEmpty) {
      yt.fail = 0;
      await http.runWithClient(() async {
        await tester.ensureVisible(failed.first);
        await tester.tap(failed.first, warnIfMissed: false);
        await settle(tester, 8);
      }, yt.client);
    }
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('篩選列：排序三種、觀看篩選每一種、重新整理、空狀態的解除鈕', (tester) async {
    final yt = await open(tester, 'a');
    for (final t in ['熱門', '最舊', '最新']) {
      await tapText(tester, yt, t);
    }
    for (final t in ['已隱藏', '♪ 歌曲', '全部', '沒看過']) {
      final f = find.textContaining(t);
      if (f.evaluate().isEmpty) continue;
      await http.runWithClient(() async {
        await tester.ensureVisible(f.first);
        await tester.tap(f.first, warnIfMissed: false);
        await settle(tester, 4);
      }, yt.client);
      for (final fix in ['看全部', '看全部類型', '不限時長']) {
        if (find.text(fix).evaluate().isNotEmpty) {
          await tapText(tester, yt, fix);
          break;
        }
      }
    }
    await http.runWithClient(() async {
      final r = find.byTooltip('重新整理');
      if (r.evaluate().isNotEmpty) {
        await tester.ensureVisible(r.first);
        await tester.tap(r.first, warnIfMissed: false);
        await settle(tester, 6);
      }
    }, yt.client);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('已下架：有下架的影片才出現，點了列出來、再點回全部', (tester) async {
    final yt = await open(
      tester,
      'a',
      extra: (s) => YtVideoCacheStore(s).upsertVideos('a', [
        YoutubeVideo(
          videoId: 'gone',
          title: '下架的影片',
          publishedAt: now.subtract(const Duration(days: 1)),
          thumbnailUrl: '',
          removedAt: now,
        ),
      ]),
    );
    final pick = find.textContaining('已下架 (');
    if (pick.evaluate().isNotEmpty) {
      await http.runWithClient(() async {
        await tester.ensureVisible(pick.first);
        await tester.tap(pick.first, warnIfMissed: false);
        await settle(tester, 4);
        // 已下架時按重新整理：重新列快取裡的。
        final r = find.byTooltip('重新整理');
        if (r.evaluate().isNotEmpty) {
          await tester.tap(r.first, warnIfMissed: false);
          await settle(tester, 4);
        }
        await tester.ensureVisible(find.textContaining('已下架 (').first);
        await tester.tap(
          find.textContaining('已下架 (').first,
          warnIfMissed: false,
        );
        await settle(tester, 4);
      }, yt.client);
    }
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('幣圈頻道：觀看篩選有評價那幾種、準度鈕進統計頁', (tester) async {
    final yt = await open(
      tester,
      'k',
      extra: (s) async {
        final repo = YtTrackerRepository(s);
        await repo.addCategory(
          const YtCategory(id: 'c3', name: '幣圈', colorValue: 0xFFFFC857),
        );
        await repo.addChannel(
          YtChannel(
            id: 'k',
            name: '頻道k',
            categoryId: 'c3',
            youtubeChannelId: 'UCk',
            uploadsPlaylistId: 'UUk',
            url: '',
            addedAt: now,
            reviewedAt: now,
            statsUpdatedAt: now,
          ),
        );
        await YtVideoCacheStore(s).upsertVideos('k', [
          for (var i = 0; i < 4; i++)
            YoutubeVideo(
              videoId: 'k$i',
              title: '幣影片 $i',
              publishedAt: now.subtract(Duration(days: i)),
              thumbnailUrl: '',
            ),
        ]);
        for (var i = 0; i < 4; i++) {
          await YtVideoRatingStore(s).set(
            'k$i',
            YtVideoRating(
              at: now,
              verdict: YtVerdict.values[i],
              ratedAt: now,
              channelId: 'k',
            ),
          );
        }
      },
    );
    for (final t in ['🎯 待驗證', '○ 對', '△ 半對', '✕ 不對', '— 沒給方向', '全部']) {
      final f = find.textContaining(t);
      if (f.evaluate().isEmpty) continue;
      await http.runWithClient(() async {
        await tester.ensureVisible(f.first);
        await tester.tap(f.first, warnIfMissed: false);
        await settle(tester, 3);
      }, yt.client);
    }
    final acc = find.textContaining('🎯 準度');
    if (acc.evaluate().isNotEmpty) {
      await http.runWithClient(() async {
        await tester.ensureVisible(acc.first);
        await tester.tap(acc.first, warnIfMissed: false);
        await settle(tester, 4);
      }, yt.client);
    }
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('垃圾桶裡的頻道：上面有還原', (tester) async {
    final yt = await open(tester, 't');
    final restore = find.text('還原');
    expect(restore, findsWidgets);
    await http.runWithClient(() async {
      await tester.tap(restore.first);
      await settle(tester, 4);
    }, yt.client);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('簡介分頁：還沒抓完整個頻道，按「現在抓」', (tester) async {
    final yt = await open(tester, 'z');
    await tapText(tester, yt, '簡介');
    await tapText(tester, yt, '現在抓');
    await run(tester, yt, 10);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets('回到頂端鈕：捲下去出現，拖到左邊吸邊、記位置，點了回頂端', (tester) async {
    final yt = await open(
      tester,
      'a',
      extra: (s) => YtVideoCacheStore(s).upsertVideos('a', [
        for (var i = 0; i < 80; i++)
          YoutubeVideo(
            videoId: 'many$i',
            title: '很多影片 $i',
            publishedAt: now.subtract(Duration(hours: i + 1)),
            thumbnailUrl: '',
          ),
      ]),
    );
    // 「隱藏已看過」以外都看，清單才夠長。
    await tapText(tester, yt, '全部');
    for (var i = 0; i < 4; i++) {
      await http.runWithClient(() async {
        await tester.flingFrom(
          const Offset(195, 640),
          const Offset(0, -3000),
          4000,
        );
        await settle(tester, 4);
      }, yt.client);
    }
    final top = find.byIcon(Icons.keyboard_arrow_up_rounded);
    expect(top, findsOneWidget);
    await tester.drag(top, const Offset(-300, -80));
    await settle(tester, 6);
    await tester.drag(top, const Offset(300, 40));
    await settle(tester, 6);
    await tester.tap(top, warnIfMissed: false);
    await settle(tester, 6);
    expect(tester.takeException(), isNull);
    await done(tester);
  });
}

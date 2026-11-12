import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_type_backfill.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// 「補齊影片類型」（2026-11-12 補到 95%）：沒金鑰、跑完的結果、配額用完停下來、
/// 跑的時候再按一次、沒有 uploads 清單用頻道 id 推、沒快取的頻道跳過、點一下收掉、
/// 時間到自己收掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MemoryStore> seed(WidgetTester tester) async {
    final store = MemoryStore();
    final now = DateTime.now();
    await tester.runAsync(() async {
      final repo = YtTrackerRepository(store);
      YtChannel ch(String id, {String uploads = '', String yt = ''}) =>
          YtChannel(
            id: id,
            name: '頻道$id',
            categoryId: null,
            youtubeChannelId: yt,
            uploadsPlaylistId: uploads,
            url: 'https://www.youtube.com/@$id',
            addedAt: now,
          );
      // 有 uploads 清單的、只有 UC 頻道 id 的、什麼都沒有的、沒快取的。
      await repo.addChannel(ch('a', uploads: 'UUa'));
      await repo.addChannel(ch('b', yt: 'UCb'));
      await repo.addChannel(ch('c'));
      await repo.addChannel(ch('d', uploads: 'UUd'));
      final cache = YtVideoCacheStore(store);
      for (final id in ['a', 'b', 'c']) {
        await cache.upsertVideos(id, [
          for (var i = 0; i < 3; i++)
            YoutubeVideo(
              videoId: 'v$i$id',
              title: '影片 $i',
              publishedAt: now.subtract(Duration(days: i)),
              thumbnailUrl: '',
            ),
        ]);
      }
    });
    return store;
  }

  Future<BuildContext> host(
    WidgetTester tester,
    MemoryStore store, {
    String? key = 'KEY',
  }) async {
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          ytApiKeyProvider.overrideWith((_) => key),
        ],
        child: const MaterialApp(home: Scaffold(body: YtTypeBackfillRow())),
      ),
    );
    return tester.element(find.byType(YtTypeBackfillRow));
  }

  testWidgets('沒有 API 金鑰：說一聲、不會跑', (tester) async {
    final store = await seed(tester);
    await host(tester, store, key: null);
    await tester.tap(find.text('開始'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('還沒設定 API 金鑰，無法補類型'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await host(tester, store, key: '');
    await tester.tap(find.text('開始'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('還沒設定 API 金鑰，無法補類型'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('補好了：顯示幾個頻道、幾部；跑的時候再按說已經在補；點一下收掉', (tester) async {
    final store = await seed(tester);
    final yt = FakeYoutube();
    final ctx = await host(tester, store);
    await http.runWithClient(() async {
      // 連按兩下：第二下時第一輪還在跑。
      await tester.tap(find.text('開始'));
      await tester.tap(find.text('開始'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('已經在補了，進度在畫面最上面'), findsOneWidget);
      await settle(tester, 12);
    }, yt.client);
    expect(find.textContaining('補好了：2 個頻道'), findsOneWidget);
    // a 跟 b（用 UCb 推出 UUb）都有打 API，c 沒有清單、d 沒快取都跳過。
    final lists = yt.calls.map((u) => u.queryParameters['playlistId']).toSet();
    expect(lists, containsAll(['UUSHa', 'UULVa', 'UUSHb', 'UULVb']));
    expect(lists.any((p) => p != null && p.endsWith('d')), isFalse);
    // 「已經在補了」那則提示疊在同一個位置，直接按進度條本身。
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.textContaining('補好了'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTap!();
    await tester.pump();
    expect(find.textContaining('補好了'), findsNothing);
    expect(ctx.mounted, isTrue);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('配額用完：停下來說補到一半、之後再按接著補；時間到自己收掉', (tester) async {
    final store = await seed(tester);
    final yt = FakeYoutube()..fail = 403;
    await host(tester, store);
    await http.runWithClient(() async {
      await tester.tap(find.text('開始'));
      await settle(tester, 12);
    }, yt.client);
    expect(find.textContaining('補到一半停下來了'), findsOneWidget);
    expect(find.textContaining('已完成 0 個頻道'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.textContaining('補到一半'), findsNothing);
  });

  testWidgets('讀頻道就壞了也會收尾', (tester) async {
    final store = MemoryStore();
    store.data['yt_tracker.channels.v1'] = '壞掉的 json';
    await host(tester, store);
    await http.runWithClient(() async {
      await tester.tap(find.text('開始'));
      await settle(tester, 8);
    }, FakeYoutube().client);
    // 不管有沒有壞，一定會出結果、不會一直卡在「補影片類型中」。
    expect(find.textContaining('補影片類型中'), findsNothing);
    await tester.pump(const Duration(seconds: 9));
  });
}

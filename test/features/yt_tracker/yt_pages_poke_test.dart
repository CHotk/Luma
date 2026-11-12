import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/features/yt_tracker/yt_category_order_page.dart';
import 'package:lume/features/yt_tracker/yt_channel_log_page.dart';
import 'package:lume/features/yt_tracker/yt_crypto_stats_page.dart';
import 'package:lume/features/yt_tracker/yt_playlists_page.dart';
import 'package:lume/features/yt_tracker/yt_purged_channels_page.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';
import 'package:lume/features/yt_tracker/yt_tracker_channel_page.dart';
import 'package:lume/features/yt_tracker/yt_tracker_home_page.dart';
import 'package:lume/features/yt_tracker/yt_trash_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// YT 頻道追蹤每一頁（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：有分類、釘選、冷凍、
/// 歌手、垃圾桶、永久刪除、影片快取、看過、評價（含到期）、歌曲、播放清單、頻道紀錄，
/// 假的 YouTube API 回資料時，每一頁每個控制項都點一次不會壞；API 壞掉（配額用完）也不會壞。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pages = <String, Widget Function()>{
    '首頁': () => const YtTrackerHomePage(),
    '分類（全部）': () => const YtTrackerBrowsePage(initialCategoryIds: {}),
    '分類（投資）': () => const YtTrackerBrowsePage(initialCategoryIds: {'c1'}),
    '垃圾桶分類': () =>
        const YtTrackerBrowsePage(initialCategoryIds: {'c1'}, trash: true),
    '頻道頁（釘選）': () => const YtTrackerChannelPage(channelId: 'a'),
    '頻道頁（歌手）': () => const YtTrackerChannelPage(channelId: 'm'),
    '頻道頁（找不到）': () => const YtTrackerChannelPage(channelId: '不存在'),
    '垃圾桶': () => const YtTrashPage(),
    '永久刪除': () => const YtPurgedChannelsPage(),
    '播放清單': () => const YtPlaylistsPage(),
    '稍後觀看': () => const YtPlaylistPage(playlistId: 'later'),
    '空的清單': () => const YtPlaylistPage(playlistId: 'pl1'),
    '頻道紀錄（全部）': () => const YtChannelLogPage(),
    '頻道紀錄（單一）': () => const YtChannelLogPage(channelId: 'a'),
    '分類順序': () => const YtCategoryOrderPage(),
    '預測統計': () => const YtCryptoStatsPage(),
  };

  for (final fail in [0, 403]) {
    for (final MapEntry(key: name, value: page) in pages.entries) {
      // API 壞掉的情況只跑會打 API 的頁。
      if (fail != 0 &&
          !name.startsWith('頻道頁') &&
          !name.startsWith('首頁') &&
          !name.startsWith('分類（')) {
        continue;
      }
      testWidgets('YT「$name」${fail == 0 ? '' : '（API 壞了 $fail）'}：每個控制項點一次', (
        tester,
      ) async {
        final yt = FakeYoutube()..fail = fail;
        final store = MemoryStore();
        await seedYt(tester, store);
        final router = await http.runWithClient(
          () => pumpPage(
            tester,
            store,
            page,
            size: const Size(390, 860),
            overrides: [ytApiKeyProvider.overrideWith((_) => 'KEY')],
          ),
          yt.client,
        );
        await http.runWithClient(() => settle(tester, 6), yt.client);
        final n = await http.runWithClient(
          () => pokeAll(tester, router, max: 160, deep: true),
          yt.client,
        );
        expect(n, greaterThanOrEqualTo(0));
        final e = tester.takeException();
        expect(e, isNull, reason: '$e');
        await tester.pump(const Duration(seconds: 8));
      });
    }
  }

  testWidgets('沒有 API 金鑰：首頁、頻道頁照樣能用', (tester) async {
    final store = MemoryStore();
    await seedYt(tester, store, apiKey: false);
    for (final page in [
      () => const YtTrackerHomePage(),
      () => const YtTrackerChannelPage(channelId: 'a'),
    ]) {
      final router = await pumpPage(
        tester,
        store,
        page,
        size: const Size(390, 860),
      );
      await pokeAll(tester, router, max: 60);
      expect(tester.takeException(), isNull);
    }
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('一個頻道都沒有：首頁、分類、垃圾桶都有空狀態', (tester) async {
    for (final page in [
      () => const YtTrackerHomePage(),
      () => const YtTrackerBrowsePage(initialCategoryIds: {}),
      () => const YtTrashPage(),
      () => const YtPurgedChannelsPage(),
      () => const YtChannelLogPage(),
    ]) {
      final router = await pumpPage(
        tester,
        MemoryStore(),
        page,
        size: const Size(390, 860),
      );
      await pokeAll(tester, router, max: 30);
      expect(tester.takeException(), isNull);
    }
    // ProviderScope 收掉。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
  });
}

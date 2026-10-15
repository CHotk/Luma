import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/services/yt_view_count_refresher.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

/// 觀看次數（2026-10-15 使用者要求）。
void main() {
  YoutubeVideo v(String id, {int? views, DateTime? at, DateTime? published}) =>
      YoutubeVideo(
        videoId: id,
        title: id,
        publishedAt: published ?? DateTime(2026),
        thumbnailUrl: '',
        viewCount: views,
        viewsAt: at,
      );

  test('次數寫法跟 YouTube 中文版一樣', () {
    expect(formatViewCount(987), '987 次');
    expect(formatViewCount(1234), '1,234 次');
    expect(formatViewCount(32000), '3.2 萬次');
    expect(formatViewCount(10000), '1 萬次');
    expect(formatViewCount(1234567), '123 萬次');
    expect(formatViewCount(920000000), '9.2 億次');
  });

  test('插在「幾天前」前面', () {
    expect(withViewsText('頻道・2 天前', 32000), '頻道・3.2 萬次・2 天前');
    expect(withViewsText('2 天前・剛從 YouTube 抓到', 5), '5 次・2 天前・剛從 YouTube 抓到');
    expect(withViewsText('頻道', 5), '頻道・5 次');
    expect(withViewsText('2 天前', null), '2 天前');
  });

  test('進頻道只重抓超過天數的，抓到的寫回快取', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    final now = DateTime(2026, 10, 15);
    await cache.save('UC', [
      v('old', views: 1, at: now.subtract(const Duration(days: 8))),
      v('fresh', views: 2, at: now.subtract(const Duration(days: 2))),
      v('none'),
      // 一個月內發的：昨天才更新過也照樣重抓。
      v(
        'new',
        views: 3,
        at: now.subtract(const Duration(days: 1)),
        published: now.subtract(const Duration(days: 10)),
      ),
    ]);
    final asked = <String>[];
    final client = MockClient((req) async {
      final ids = req.url.queryParameters['id']!.split(',');
      asked.addAll(ids);
      return http.Response(
        jsonEncode({
          'items': [
            for (final id in ids)
              {
                'id': id,
                'statistics': {'viewCount': '100'},
              },
          ],
        }),
        200,
      );
    });
    final n = await http.runWithClient(
      () => YtViewCountRefresher(
        store,
        const YoutubeApiService('k'),
      ).refreshIfDue('UC', every: const Duration(days: 7), now: now),
      () => client,
    );
    expect(n, 3);
    expect(asked..sort(), ['new', 'none', 'old']);
    final byId = {for (final x in await cache.load('UC')) x.videoId: x};
    expect(byId['old']!.viewCount, 100);
    expect(byId['none']!.viewsAt, now);
    expect(byId['fresh']!.viewCount, 2);
  });

  test('兩台合併：留比較新抓到的次數', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.save('UC', [v('a', views: 10, at: DateTime(2026, 10, 1))]);
    await cache.mergeFromCloud('UC', [
      v('a', views: 50, at: DateTime(2026, 10, 9)),
    ], null);
    expect((await cache.load('UC')).single.viewCount, 50);
    await cache.mergeFromCloud('UC', [
      v('a', views: 5, at: DateTime(2026, 9, 1)),
    ], null);
    expect((await cache.load('UC')).single.viewCount, 50);
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

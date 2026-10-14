import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/services/yt_channel_filler.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-14 使用者要求：進頻道就在背景把影片全部抓完；快取之前（新發的）
/// 跟之後（更舊的）都要補齊，中間不能漏。
void main() {
  setUp(YtChannelFiller.resetAll);

  // 頻道一共 130 部：v0（最新）… v129（最舊），一頁 50 部。
  final all = [for (var i = 0; i < 130; i++) i];
  YoutubeVideo video(int i) => YoutubeVideo(
    videoId: 'v$i',
    title: '影片 $i',
    publishedAt: DateTime(2026, 1, 1).subtract(Duration(days: i)),
    thumbnailUrl: '',
  );
  Map<String, dynamic> item(int i) => {
    'snippet': {
      'resourceId': {'videoId': 'v$i'},
      'title': '影片 $i',
      'publishedAt': DateTime(
        2026,
        1,
        1,
      ).subtract(Duration(days: i)).toIso8601String(),
      'thumbnails': {
        'default': {'url': ''},
      },
    },
  };

  Future<List<String?>> run(YtVideoCacheStore cache) async {
    final asked = <String?>[];
    final client = MockClient((req) async {
      if (!req.url.path.endsWith('playlistItems')) {
        return http.Response('{"items":[]}', 200);
      }
      final token = req.url.queryParameters['pageToken'];
      asked.add(token);
      final start = token == null
          ? 0
          : (int.parse(token.substring(1)) - 1) * 50;
      final page = all.skip(start).take(50).toList();
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'items': [for (final i in page) item(i)],
            if (start + 50 < all.length) 'nextPageToken': 'p${start ~/ 50 + 2}',
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final filler = YtChannelFiller.of('ch');
    await http.runWithClient(
      () => filler.start(
        cache: cache,
        api: const YoutubeApiService('k'),
        uploadsId: () async => 'UUx',
      ),
      () => client,
    );
    expect(filler.error, isNull);
    expect(filler.complete, isTrue);
    return asked;
  }

  test('上次之後新發了 10 部：補最新碰到快取就停，再從記下的位置補到最舊', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.upsertVideos('ch', [for (var i = 10; i < 50; i++) video(i)]);
    await cache.saveResumeIfDeeper(
      'ch',
      const YtResume(token: 'p2', offset: 50, end: false),
    );
    final asked = await run(cache);
    expect(asked, [null, 'p2', 'p3']);
    final ids = {for (final v in await cache.load('ch')) v.videoId};
    expect(ids.length, 130);
    expect(ids, containsAll(['v0', 'v9', 'v50', 'v129']));
  });

  test('新發的超過一頁（快取前面缺 60 部）：一路補到碰到快取，中間不漏', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    await cache.upsertVideos('ch', [for (var i = 60; i < 100; i++) video(i)]);
    await cache.saveResumeIfDeeper(
      'ch',
      const YtResume(token: 'p3', offset: 100, end: false),
    );
    final asked = await run(cache);
    expect(asked, [null, 'p2', 'p3']);
    final ids = {for (final v in await cache.load('ch')) v.videoId};
    expect(ids.length, 130);
    for (var i = 0; i < 130; i++) {
      expect(ids, contains('v$i'));
    }
  });

  test('從來沒抓過：從頭翻到底；抓完 10 分鐘內再叫不再打 API', () async {
    final cache = YtVideoCacheStore(_MemoryStore());
    expect(await run(cache), [null, 'p2', 'p3']);
    expect((await cache.load('ch')).length, 130);
    expect(YtChannelFiller.of('ch').cached, 130);
    expect(await run(cache), isEmpty);
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

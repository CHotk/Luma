import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/repositories/yt_search_recents_store.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/services/yt_channel_filler.dart';
import 'package:lume/data/services/yt_channel_search.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-14 頻道頁搜尋：先找快取，再從快取記下的位置接著把整個頻道
/// 抓完；快取已經有的那段不重抓；抓過的存進快取，第二次搜不打 API。
void main() {
  setUp(YtChannelFiller.resetAll);

  // 頻道一共 130 部：v0（最新）… v129（最舊）。
  String title(int i) => i % 10 == 3 ? '黑洞的祕密 $i' : '其他影片 $i';
  final all = [for (var i = 0; i < 130; i++) i];

  YoutubeVideo video(int i) => YoutubeVideo(
    videoId: 'v$i',
    title: title(i),
    publishedAt: DateTime(2026, 1, 1).subtract(Duration(days: i)),
    thumbnailUrl: '',
  );

  Map<String, dynamic> item(int i) => {
    'snippet': {
      'resourceId': {'videoId': 'v$i'},
      'title': title(i),
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

  test('快取先出結果，接著從記下的位置抓到頻道最舊，存進快取；第二次只搜快取', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    // 快取已經有最新的 50 部，位置記在第 2 頁。
    await cache.upsertVideos('ch', [for (final i in all.take(50)) video(i)]);
    await cache.saveResumeIfDeeper(
      'ch',
      const YtResume(token: 'p2', offset: 50, end: false),
    );

    final askedTokens = <String?>[];
    final client = MockClient((req) async {
      // 補時長（videos.list）不算翻頁，回空的就好。
      if (!req.url.path.endsWith('playlistItems')) {
        return http.Response('{"items":[]}', 200);
      }
      final token = req.url.queryParameters['pageToken'];
      askedTokens.add(token);
      final start = switch (token) {
        null => 0,
        'p2' => 50,
        'p3' => 100,
        _ => throw StateError('不該要 $token'),
      };
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

    final search = YtChannelSearch(
      channelId: 'ch',
      query: '黑洞',
      cache: cache,
      api: const YoutubeApiService('k'),
      uploadsId: () async => 'UUx',
      totalOnYoutube: 130,
    );
    final seen = <int>[];
    search.addListener(() => seen.add(search.matches.length));
    await http.runWithClient(search.run, () => client);

    // 第一個通知是快取的結果（50 部裡 5 部）。
    expect(search.error, isNull);
    expect(seen.first, 5);
    expect(search.done, isTrue);
    expect(search.error, isNull);
    // 先看最新那頁（全是快取有的 → 不用再往下補最新），再從記下的第 2 頁
    // 接著翻到底；中間沒有從頭重翻。
    expect(askedTokens, [null, 'p2', 'p3']);
    expect(search.matches.length, 13);
    expect(search.scanned, 130);
    expect(search.fetchedIds.length, 80);
    expect(search.matches.first.videoId, 'v3');
    expect((await cache.load('ch')).length, 130);
    expect((await cache.loadResume('ch'))!.end, isTrue);

    // 第二次搜：整個頻道都在快取，不打 API。
    askedTokens.clear();
    final again = YtChannelSearch(
      channelId: 'ch',
      query: '黑洞',
      cache: cache,
      api: const YoutubeApiService('k'),
      uploadsId: () async => 'UUx',
    );
    await http.runWithClient(again.run, () => client);
    expect(askedTokens, isEmpty);
    expect(again.matches.length, 13);
    expect(again.done, isTrue);
  });

  test('只搜快取：不打 API，大小寫不分', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('ch', [
      YoutubeVideo(
        videoId: 'a',
        title: 'Minecraft 生存',
        publishedAt: DateTime(2026),
        thumbnailUrl: '',
      ),
      YoutubeVideo(
        videoId: 'b',
        title: '其他',
        publishedAt: DateTime(2026),
        thumbnailUrl: '',
      ),
    ]);
    final search = YtChannelSearch(
      channelId: 'ch',
      query: 'minecraft',
      cache: cache,
    );
    await search.run();
    expect(search.usesApi, isFalse);
    expect(search.done, isTrue);
    expect(search.matches.map((v) => v.videoId), ['a']);
  });

  test('最近搜尋：最新在前、不重複、可以刪', () async {
    final r = YtSearchRecentsStore(_MemoryStore());
    await r.add('黑洞');
    await r.add('宇宙');
    expect(await r.add('黑洞'), ['黑洞', '宇宙']);
    expect(await r.remove('黑洞'), ['宇宙']);
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

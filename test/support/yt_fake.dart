import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/repositories/yt_api_key_store.dart';
import 'package:lume/data/repositories/yt_channel_log_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/data/repositories/yt_video_song_store.dart';
import 'package:lume/data/repositories/yt_video_watch_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';

import 'poke.dart';

/// 測試用的假 YouTube API：頻道、影片清單（翻兩頁）、影片時長／觀看數、搜尋都回固定資料。
/// [fail] 設了就每支請求都回那個狀態碼（測錯誤畫面）。
class FakeYoutube {
  int fail = 0;
  final calls = <Uri>[];

  http.Client client() => MockClient((req) async {
    calls.add(req.url);
    if (fail != 0) {
      return _json({
        'error': {
          'message': 'fake error',
          'errors': [
            {'reason': fail == 403 ? 'quotaExceeded' : 'backendError'},
          ],
        },
      }, fail);
    }
    final q = req.url.queryParameters;
    switch (req.url.pathSegments.last) {
      case 'channels':
        final ids = (q['id'] ?? q['forHandle'] ?? 'UC1').split(',');
        return _json({
          'items': [
            for (final id in ids)
              {
                'id': id.startsWith('@') ? 'UCnew' : id,
                'snippet': {
                  'title': '頻道 $id',
                  'description': '介紹',
                  'thumbnails': {
                    'default': {'url': ''},
                  },
                },
                'contentDetails': {
                  'relatedPlaylists': {
                    'uploads': 'UU${id.replaceAll('@', '')}',
                  },
                },
                'statistics': {'subscriberCount': '1234', 'videoCount': '40'},
              },
          ],
        });
      case 'playlistItems':
        final page2 = q['pageToken'] == 'P2';
        final now = DateTime.now().toUtc();
        return _json({
          'items': [
            for (var i = 0; i < 5; i++)
              {
                'snippet': {
                  'resourceId': {
                    'videoId': 'v${page2 ? i + 5 : i}${q['playlistId']}',
                  },
                  'title': '影片 ${page2 ? i + 5 : i}',
                  'publishedAt': now
                      .subtract(Duration(days: (page2 ? i + 5 : i) * 3))
                      .toIso8601String(),
                  'thumbnails': {
                    'default': {'url': ''},
                  },
                },
              },
          ],
          if (!page2) 'nextPageToken': 'P2',
        });
      case 'videos':
        final ids = (q['id'] ?? '').split(',');
        return _json({
          'items': [
            for (var i = 0; i < ids.length; i++)
              {
                'id': ids[i],
                'snippet': {
                  'title': '影片',
                  'channelTitle': '頻道',
                  'publishedAt': DateTime.now().toUtc().toIso8601String(),
                  'thumbnails': <String, dynamic>{},
                  'liveBroadcastContent': i % 5 == 4 ? 'live' : 'none',
                },
                'contentDetails': {'duration': i.isEven ? 'PT45S' : 'PT12M3S'},
                'statistics': {'viewCount': '${1000 * (i + 1)}'},
              },
          ],
        });
      case 'search':
        return _json({
          'items': [
            {
              'id': {'channelId': 'UCfound', 'kind': 'youtube#channel'},
              'snippet': {
                'channelId': 'UCfound',
                'title': '搜到的頻道',
                'channelTitle': '搜到的頻道',
                'description': '',
                'thumbnails': {
                  'default': {'url': ''},
                },
              },
            },
          ],
        });
    }
    return _json({'items': []});
  });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// 塞一份完整的 YT 資料：兩個分類、五個頻道（釘選、冷凍、歌手、未分類、待評鑑）、垃圾桶一個、
/// 永久刪除一個、每個頻道的影片快取、看過、評價、歌曲、播放清單、頻道紀錄、API 金鑰。
Future<void> seedYt(
  WidgetTester tester,
  MemoryStore store, {
  bool apiKey = true,
}) async {
  final now = DateTime.now();
  final repo = YtTrackerRepository(store);
  await tester.runAsync(() async {
    if (apiKey) await YtApiKeyStore(store).save('KEY');
    await repo.addCategory(
      const YtCategory(id: 'c1', name: '投資', colorValue: 0xFF5FC9A8),
    );
    await repo.addCategory(
      const YtCategory(id: 'c2', name: '音樂', colorValue: 0xFFE07A7A),
    );
    YtChannel ch(
      String id,
      String? cat, {
      DateTime? pinned,
      DateTime? cold,
      DateTime? artist,
      DateTime? reviewed,
    }) => YtChannel(
      id: id,
      name: '頻道$id',
      categoryId: cat,
      youtubeChannelId: 'UC$id',
      uploadsPlaylistId: 'UU$id',
      url: 'https://www.youtube.com/@$id',
      addedAt: now.subtract(const Duration(days: 40)),
      subscriberCount: 12000,
      videoCount: 40,
      pinnedAt: pinned,
      coldAt: cold,
      artistAt: artist,
      reviewedAt: reviewed,
      description: '這是頻道 $id 的介紹',
    );
    await repo.addChannel(ch('a', 'c1', pinned: now));
    await repo.addChannel(ch('b', 'c1', cold: now));
    await repo.addChannel(ch('m', 'c2', artist: now, reviewed: now));
    await repo.addChannel(ch('n', null, reviewed: now));
    // 挖掘找到、還沒評鑑的。
    await repo.addChannel(ch('r', 'c1'));
    await repo.addChannel(ch('t', 'c1'));
    await repo.deleteChannel('t');
    await repo.addChannel(ch('p', 'c2'));
    await repo.deleteChannel('p');
    await repo.purgeChannel('p');
    final cache = YtVideoCacheStore(store);
    for (final id in ['a', 'b', 'm', 'n']) {
      await cache.upsertVideos(id, [
        for (var i = 0; i < 6; i++)
          YoutubeVideo(
            videoId: 'v$i$id',
            title: '頻道$id 的影片 $i',
            publishedAt: now.subtract(Duration(days: i * 4, hours: 1)),
            thumbnailUrl: '',
            duration: Duration(seconds: i.isEven ? 40 : 700),
            isShort: i.isEven,
            isLive: i == 5,
            viewCount: 1000 * (i + 1),
            viewsAt: now,
          ),
      ]);
    }
    final watch = YtVideoWatchStore(store);
    await watch.markOpened('v1a', channelId: 'a');
    await watch.markOpened('v2m', channelId: 'm');
    await YtVideoRatingStore(store).set(
      'v1a',
      YtVideoRating(
        at: now,
        verdict: YtVerdict.ok,
        claim: '會漲',
        channelId: 'a',
        channelName: '頻道a',
        title: '頻道a 的影片 1',
        ratedAt: now,
      ),
    );
    await YtVideoRatingStore(store).set(
      'v3a',
      YtVideoRating(
        at: now,
        claim: '會跌',
        dueAt: now.subtract(const Duration(days: 1)),
        channelId: 'a',
      ),
    );
    await YtVideoSongStore(store).set('v2m', true);
    final playlists = YtPlaylistStore(store);
    final later = (await playlists.loadAll()).first;
    await playlists.saveAll([
      later.copyWith(
        items: [
          YtPlaylistItem(
            video: YoutubeVideo(
              videoId: 'v0a',
              title: '稍後看的',
              publishedAt: now,
              thumbnailUrl: '',
            ),
            channelName: '頻道a',
            channelId: 'a',
            addedAt: now,
          ),
        ],
      ),
      YtPlaylist(id: 'pl1', name: '我的清單', createdAt: now, updatedAt: now),
    ]);
    await YtChannelLogStore(store).addAll([
      YtChannelEvent(
        id: 'e1',
        channelId: 'a',
        at: now,
        type: YtChannelEventType.added,
        detail: const {'category': '投資'},
      ),
      YtChannelEvent(
        id: 'e2',
        channelId: 'a',
        at: now,
        type: YtChannelEventType.values[1],
        detail: const {'from': '投資', 'to': '音樂'},
      ),
    ]);
  });
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/services/channel_discovery_service.dart';
import 'package:lume/domain/models/yt_tracker.dart';

/// 用假的 YouTube API 回應把整段挖掘流程跑一遍（沒有真的連網路）：
/// 種子頻道的推薦 → 排除 App 已有的 → 批次驗證 → 品質篩選 → 活躍度檢查。
http.Response _json(Map<String, dynamic> body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final now = DateTime.now();
  String iso(DateTime t) => t.toUtc().toIso8601String();

  Map<String, dynamic> channelItem(
    String id, {
    int subs = 5000,
    int videos = 50,
    bool hidden = false,
    String handle = '',
  }) => {
    'id': id,
    'snippet': {
      'title': '頻道 $id',
      'description': '這是 $id 的簡介',
      'customUrl': handle,
      'thumbnails': {
        'high': {'url': 'https://img/$id=s800-c-k'},
      },
    },
    'statistics': {
      'subscriberCount': '$subs',
      'videoCount': '$videos',
      'hiddenSubscriberCount': hidden,
    },
    'contentDetails': {
      'relatedPlaylists': {'uploads': 'UU$id'},
    },
  };

  test('挖掘流程：排除已有、隱藏訂閱、太少訂閱、久沒更新，只留合格的新頻道', () async {
    // 推薦名單：EXIST 已經在 App 裡，其他都是候選。
    const recommended = [
      'EXIST',
      'GOOD1',
      'GOOD2',
      'HIDDEN',
      'SMALL',
      'FEWVID',
      'STALE',
      'HANDLEDUP',
    ];
    final client = MockClient((request) async {
      final path = request.url.path;
      Map<String, dynamic> body;
      if (path.endsWith('/channelSections')) {
        body = {
          'items': [
            {
              'contentDetails': {'channels': recommended},
            },
          ],
        };
      } else if (path.endsWith('/channels')) {
        final ids = request.url.queryParameters['id']!.split(',');
        final all = {
          'GOOD1': channelItem('GOOD1'),
          'GOOD2': channelItem('GOOD2'),
          'HIDDEN': channelItem('HIDDEN', hidden: true),
          'SMALL': channelItem('SMALL', subs: 300),
          'FEWVID': channelItem('FEWVID', videos: 2),
          'STALE': channelItem('STALE'),
          // 頻道 ID 不同，但 @handle 跟 App 裡已有的一樣 → 也要排除
          'HANDLEDUP': channelItem('HANDLEDUP', handle: '@Known'),
        };
        body = {
          'items': [
            for (final id in ids)
              if (all.containsKey(id)) all[id]!,
          ],
        };
      } else if (path.endsWith('/playlistItems')) {
        final playlist = request.url.queryParameters['playlistId']!;
        final stale = playlist == 'UUSTALE';
        body = {
          'items': [
            {
              'contentDetails': {
                'videoPublishedAt': iso(
                  now.subtract(Duration(days: stale ? 400 : 10)),
                ),
              },
            },
          ],
        };
      } else if (path.endsWith('/search')) {
        // 推薦名單不夠多時會改用關鍵字搜尋影片；這裡搜不到新頻道。
        body = {'items': []};
      } else {
        return http.Response('{"error":{"message":"unexpected $path"}}', 404);
      }
      return _json(body);
    });

    final existing = [
      YtChannel(
        id: 'seed-a',
        name: 'A',
        categoryId: null,
        youtubeChannelId: 'EXIST',
        addedAt: now,
      ),
      YtChannel(
        id: 'seed-known',
        name: 'Known',
        categoryId: null,
        url: 'https://youtube.com/@known?si=abc',
        addedAt: now,
      ),
    ];

    final found = await ChannelDiscoveryService(
      'fake-key',
      random: Random(1),
      client: client,
    ).discover(existing: existing, keywords: const ['知識'], count: 10);

    expect(found.map((c) => c.channelId).toSet(), {'GOOD1', 'GOOD2'});
    final g = found.firstWhere((c) => c.channelId == 'GOOD1');
    expect(g.title, '頻道 GOOD1');
    expect(g.avatarUrl, contains('=s160-c-k-c0x00ffffff-no-rj'));
    expect(g.url, 'https://www.youtube.com/channel/GOOD1');
    expect(g.uploadsPlaylistId, 'UUGOOD1');
    expect(g.subscriberCount, 5000);
  });

  test('一次最多挖 count 個', () async {
    final ids = [for (var i = 0; i < 30; i++) 'C$i'];
    final client = MockClient((request) async {
      final path = request.url.path;
      final Map<String, dynamic> body;
      if (path.endsWith('/channelSections')) {
        body = {
          'items': [
            {
              'contentDetails': {'channels': ids},
            },
          ],
        };
      } else if (path.endsWith('/channels')) {
        body = {
          'items': [
            for (final id in request.url.queryParameters['id']!.split(','))
              channelItem(id),
          ],
        };
      } else {
        body = {
          'items': [
            {
              'contentDetails': {'videoPublishedAt': iso(now)},
            },
          ],
        };
      }
      return _json(body);
    });
    final found =
        await ChannelDiscoveryService(
          'fake-key',
          random: Random(2),
          client: client,
        ).discover(
          existing: [
            YtChannel(
              id: 'seed',
              name: 's',
              categoryId: null,
              youtubeChannelId: 'SEED',
              addedAt: now,
            ),
          ],
          keywords: const [],
          count: 10,
        );
    expect(found.length, 10);
    expect(found.map((c) => c.channelId).toSet().length, 10);
  });

  test('已刪除的頻道不會再被挖到；自訂關鍵字一定會拿去搜尋影片', () async {
    final searchedQueries = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      final Map<String, dynamic> body;
      if (path.endsWith('/channelSections')) {
        body = {
          'items': [
            {
              'contentDetails': {
                'channels': ['DELETED', 'FRESH'],
              },
            },
          ],
        };
      } else if (path.endsWith('/search')) {
        searchedQueries.add(request.url.queryParameters['q']!);
        body = {
          'items': [
            {
              'snippet': {'channelId': 'FROMSEARCH'},
            },
          ],
        };
      } else if (path.endsWith('/channels')) {
        body = {
          'items': [
            for (final id in request.url.queryParameters['id']!.split(','))
              channelItem(id),
          ],
        };
      } else {
        body = {
          'items': [
            {
              'contentDetails': {'videoPublishedAt': iso(now)},
            },
          ],
        };
      }
      return _json(body);
    });

    final deleted = YtChannel(
      id: 'gone',
      name: '刪掉的',
      categoryId: null,
      youtubeChannelId: 'DELETED',
      addedAt: now,
      deletedAt: now,
    );
    final seed = YtChannel(
      id: 'seed',
      name: 's',
      categoryId: 'cat',
      youtubeChannelId: 'SEED',
      addedAt: now,
    );
    final found =
        await ChannelDiscoveryService(
          'fake-key',
          random: Random(3),
          client: client,
        ).discover(
          existing: [seed, deleted],
          seeds: [seed],
          keywords: const [],
          priorityKeyword: '露營',
          count: 10,
        );
    final ids = found.map((c) => c.channelId).toSet();
    expect(ids, {'FRESH', 'FROMSEARCH'});
    expect(ids, isNot(contains('DELETED')));
    expect(searchedQueries.first, '露營');
  });
}

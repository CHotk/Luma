import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/services/youtube_api_service.dart';

/// YouTube API 每支請求的解析跟錯誤（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 頻道（@帳號／UC…、找不到、訂閱數隱藏）、訂閱人數一批 50 個、影片清單翻頁（遇到看過的就停、
/// 早於 since 就停、上限頁數）、單一影片、時長／觀看數、下架檢查、配額用完／金鑰錯／其他錯誤。
void main() {
  const api = YoutubeApiService('k');

  Map<String, dynamic> playlistItem(String id, DateTime at) => {
    'snippet': {
      'resourceId': {'videoId': id},
      'title': '影片 $id',
      'publishedAt': at.toUtc().toIso8601String(),
      'thumbnails': {
        'default': {'url': 'https://t/$id.jpg'},
      },
    },
  };

  Future<T> withApi<T>(
    Future<T> Function() run,
    http.Response Function(http.Request req) handler, {
    List<http.Request>? log,
  }) => http.runWithClient(
    run,
    () => MockClient((req) async {
      log?.add(req);
      return handler(req);
    }),
  );

  http.Response ok(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('影片物件：with… 每個都只改一個欄位；JSON 來回；Shorts 判斷', () {
    final v = YoutubeVideo(
      videoId: 'v',
      title: 't',
      publishedAt: DateTime.utc(2026, 1, 1),
      thumbnailUrl: 'u',
    );
    expect(v.isLikelyShort, isFalse);
    expect(v.withDuration(const Duration(seconds: 50)).isLikelyShort, isTrue);
    expect(v.withDuration(Duration.zero).isLikelyShort, isFalse);
    expect(
      v.withShort(false).withDuration(const Duration(seconds: 5)).isLikelyShort,
      isFalse,
    );
    expect(v.withLive(true).isLive, isTrue);
    final r = v.withRemoved(DateTime.utc(2026, 2, 1));
    expect(r.removedAt, isNotNull);
    expect(r.withRemoved(null).removedAt, isNull);
    final w = v.withViews(99, DateTime.utc(2026, 3, 1));
    final back = YoutubeVideo.fromJson(jsonDecode(jsonEncode(w.toJson())));
    expect(back.viewCount, 99);
    expect(back.viewsAt, DateTime.utc(2026, 3, 1));
    expect(back.duration, isNull);
    expect(v.watchUrl, 'https://www.youtube.com/watch?v=v');
    expect(YoutubeApiException('x', status: 404).toString(), 'x');
  });

  test('時長字串：只有秒、時分秒、看不懂＝0；顯示補零', () {
    expect(parseIso8601Duration('PT45S'), const Duration(seconds: 45));
    expect(
      parseIso8601Duration('PT1H2M10S'),
      const Duration(hours: 1, minutes: 2, seconds: 10),
    );
    expect(parseIso8601Duration('亂寫'), Duration.zero);
    expect(formatVideoDuration(const Duration(minutes: 4, seconds: 3)), '4:03');
    expect(
      formatVideoDuration(const Duration(hours: 1, seconds: 5)),
      '1:00:05',
    );
  });

  test('網址解析：@帳號、/channel/UC…、都沒有＝null；影片 ID 各種寫法', () {
    expect(
      YoutubeApiService.parseHandle('https://youtube.com/@abc.def'),
      '@abc.def',
    );
    expect(
      YoutubeApiService.parseHandle('https://youtube.com/channel/UCxyz_1'),
      'UCxyz_1',
    );
    expect(YoutubeApiService.parseHandle(''), isNull);
    for (final s in [
      'https://youtu.be/abcdefghijk',
      'https://www.youtube.com/watch?v=abcdefghijk&t=1',
      'https://youtube.com/shorts/abcdefghijk',
      '看這個 https://music.youtube.com/watch?v=abcdefghijk 好聽',
      ' abcdefghijk ',
    ]) {
      expect(YoutubeApiService.parseVideoId(s), 'abcdefghijk', reason: s);
    }
    expect(YoutubeApiService.parseVideoId('太短'), isNull);
  });

  group('頻道', () {
    Map<String, dynamic> channel({bool hidden = false}) => {
      'items': [
        {
          'id': 'UC1',
          'snippet': {
            'title': '頻道',
            'description': '  介紹  ',
            'thumbnails': {
              'medium': {'url': 'https://a/m.jpg'},
            },
          },
          'contentDetails': {
            'relatedPlaylists': {'uploads': 'UU1'},
          },
          'statistics': {
            'subscriberCount': '1200',
            'hiddenSubscriberCount': hidden,
            'videoCount': '33',
          },
        },
      ],
    };

    test('用 @帳號 查：forHandle；訂閱數、影片數、頭像、介紹去空白', () async {
      final log = <http.Request>[];
      final c = await withApi(
        () => api.fetchChannelInfo('@abc'),
        (_) => ok(channel()),
        log: log,
      );
      expect(log.single.url.queryParameters['forHandle'], '@abc');
      expect(c.uploadsPlaylistId, 'UU1');
      expect(c.subscriberCount, 1200);
      expect(c.videoCount, 33);
      expect(c.avatarUrl, 'https://a/m.jpg');
      expect(c.description, '介紹');
    });

    test('用 UC… 查：id；訂閱數隱藏＝null', () async {
      final log = <http.Request>[];
      final c = await withApi(
        () => api.fetchChannelInfo('UC1'),
        (_) => ok(channel(hidden: true)),
        log: log,
      );
      expect(log.single.url.queryParameters['id'], 'UC1');
      expect(c.subscriberCount, isNull);
      expect(c.subscribersHidden, isTrue);
    });

    test('找不到頻道（items 空）', () async {
      await expectLater(
        withApi(() => api.fetchChannelInfo('@nope'), (_) => ok({'items': []})),
        throwsA(
          isA<YoutubeApiException>().having(
            (e) => e.message,
            'm',
            contains('找不到頻道 @nope'),
          ),
        ),
      );
    });

    test('訂閱人數：一次最多 50 個，超過分兩批；隱藏的 count 是 null', () async {
      final ids = [for (var i = 0; i < 51; i++) 'C$i'];
      final log = <http.Request>[];
      final r = await withApi(
        () => api.fetchSubscriberStats(ids),
        (req) => ok({
          'items': [
            for (final id in req.url.queryParameters['id']!.split(','))
              {
                'id': id,
                'statistics': {
                  'subscriberCount': '10',
                  'hiddenSubscriberCount': id == 'C0',
                  'videoCount': '2',
                },
              },
          ],
        }),
        log: log,
      );
      expect(log, hasLength(2));
      expect(r, hasLength(51));
      expect(r['C0']!.count, isNull);
      expect(r['C0']!.hidden, isTrue);
      expect(r['C50']!.count, 10);
    });
  });

  group('影片清單', () {
    final now = DateTime.utc(2026, 11, 1);

    test('一頁：帶 pageToken、回下一頁 token', () async {
      final log = <http.Request>[];
      final p = await withApi(
        () => api.fetchVideosPage('UU1', pageToken: 'T1', maxResults: 5),
        (_) => ok({
          'items': [playlistItem('a', now)],
          'nextPageToken': 'T2',
        }),
        log: log,
      );
      expect(log.single.url.queryParameters['pageToken'], 'T1');
      expect(p.videos.single.thumbnailUrl, 'https://t/a.jpg');
      expect(p.nextPageToken, 'T2');
      final recent = await withApi(
        () => api.fetchRecentVideos('UU1', maxResults: 1),
        (_) => ok({
          'items': [playlistItem('b', now)],
        }),
      );
      expect(recent.single.videoId, 'b');
    });

    test('全部：翻到看過的影片就停；早於 since 的不要、也停；沒下一頁就停；頁數上限', () async {
      var page = 0;
      final offsets = <int>[];
      final got = await withApi(
        () => api.fetchAllVideos(
          'UU1',
          since: now.subtract(const Duration(days: 30)),
          knownVideoIds: {'k'},
          onPage: (_, o) => offsets.add(o),
        ),
        (_) {
          page++;
          return ok({
            'items': page == 1
                ? [playlistItem('n1', now), playlistItem('n2', now)]
                : [playlistItem('k', now), playlistItem('n3', now)],
            'nextPageToken': 'more',
          });
        },
      );
      expect(page, 2);
      expect(offsets, [2, 4]);
      expect(got.map((v) => v.videoId), ['n1', 'n2', 'k', 'n3']);

      page = 0;
      final old = await withApi(() => api.fetchAllVideos('UU1', since: now), (
        _,
      ) {
        page++;
        return ok({
          'items': [
            playlistItem('new', now),
            playlistItem('old', now.subtract(const Duration(days: 1))),
          ],
          'nextPageToken': 'more',
        });
      });
      expect(page, 1);
      expect(old.map((v) => v.videoId), ['new']);

      page = 0;
      await withApi(
        () => api.fetchAllVideos('UU1', since: DateTime.utc(2000), maxPages: 3),
        (_) {
          page++;
          return ok({'items': [], 'nextPageToken': 'more'});
        },
      );
      expect(page, 3);

      page = 0;
      await withApi(
        () => api.fetchAllVideos('UU1', since: DateTime.utc(2000)),
        (_) {
          page++;
          return ok({
            'items': [playlistItem('x', now)],
          });
        },
      );
      expect(page, 1);
    });
  });

  group('影片資料', () {
    test('單一影片：有資料、找不到＝null、沒縮圖用預設網址、沒時長＝null', () async {
      final info = await withApi(
        () => api.fetchVideoInfo('abcdefghijk'),
        (_) => ok({
          'items': [
            {
              'snippet': {
                'title': '歌',
                'channelTitle': '歌手',
                'publishedAt': '2026-01-01T00:00:00Z',
                'thumbnails': {
                  'high': {'url': 'https://h.jpg'},
                },
              },
              'contentDetails': {'duration': 'PT3M5S'},
            },
          ],
        }),
      );
      expect(info!.title, '歌');
      expect(info.channelName, '歌手');
      expect(info.thumbnailUrl, 'https://h.jpg');
      expect(info.duration, const Duration(minutes: 3, seconds: 5));
      final bare = await withApi(
        () => api.fetchVideoInfo('abcdefghijk'),
        (_) => ok({
          'items': [
            {'snippet': <String, dynamic>{}},
          ],
        }),
      );
      expect(bare!.thumbnailUrl, contains('abcdefghijk'));
      expect(bare.duration, isNull);
      expect(bare.title, '');
      expect(
        await withApi(() => api.fetchVideoInfo('x'), (_) => ok({'items': []})),
        isNull,
      );
    });

    Map<String, dynamic> vid(String id, {String? views}) => {
      'id': id,
      'contentDetails': {'duration': 'PT1M'},
      'statistics': {'viewCount': ?views},
    };

    test('時長、時長＋觀看數、只抓觀看數（沒有觀看數的不放）、空的不打 API', () async {
      expect(await api.fetchDurations(const []), isEmpty);
      final d = await withApi(
        () => api.fetchDurations(['a']),
        (_) => ok({
          'items': [vid('a')],
        }),
      );
      expect(d['a'], const Duration(minutes: 1));
      final det = await withApi(
        () => api.fetchDetails(['a', 'b']),
        (_) => ok({
          'items': [vid('a', views: '5'), vid('b')],
        }),
      );
      expect(det['a']!.views, 5);
      expect(det['b']!.views, isNull);
      final views = await withApi(
        () => api.fetchViewCounts(['a', 'b']),
        (_) => ok({
          'items': [vid('a', views: '7'), vid('b')],
        }),
      );
      expect(views, {'a': 7});
    });

    test('下架檢查：沒回來的就是下架', () async {
      final ids = [for (var i = 0; i < 60; i++) 'v$i'];
      final log = <http.Request>[];
      final alive = await withApi(
        () => api.fetchExistingVideoIds(ids),
        (req) => ok({
          'items': [
            for (final id in req.url.queryParameters['id']!.split(','))
              if (id != 'v3') {'id': id},
          ],
        }),
        log: log,
      );
      expect(log, hasLength(2));
      expect(alive, hasLength(59));
      expect(alive.contains('v3'), isFalse);
    });
  });

  group('錯誤', () {
    http.Response err(int status, {String? reason, String? message}) =>
        http.Response(
          jsonEncode({
            'error': {
              'message': ?message,
              'errors': [
                if (reason != null) {'reason': reason},
              ],
            },
          }),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    final calls = <String, Future<Object?> Function()>{
      '頻道': () => api.fetchChannelInfo('@a'),
      '訂閱人數': () => api.fetchSubscriberStats(['a']),
      '一頁影片': () => api.fetchVideosPage('UU'),
      '全部影片': () => api.fetchAllVideos('UU', since: DateTime.utc(2000)),
      '時長': () => api.fetchDurations(['a']),
      '觀看數': () => api.fetchViewCounts(['a']),
      '下架檢查': () => api.fetchExistingVideoIds(['a']),
    };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('$name：配額用完、金鑰錯、其他錯誤（用 API 給的訊息，沒有就寫狀態碼）', () async {
        Future<void> expectMsg(http.Response r, String words) => expectLater(
          withApi(call, (_) => r),
          throwsA(
            isA<YoutubeApiException>().having(
              (e) => e.message,
              'm',
              contains(words),
            ),
          ),
        );
        await expectMsg(err(403, reason: 'quotaExceeded'), '配額用完');
        await expectMsg(err(400), 'API 金鑰不對');
        await expectMsg(err(500, message: 'Backend Error'), 'Backend Error');
        await expectMsg(err(404), '狀態碼 404');
      });
    }
  });
}

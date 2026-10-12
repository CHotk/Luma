import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/services/yt_removed_video_checker.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 2026-10-12 使用者要求：超過兩週就把快取裡的影片編號丟回 YouTube 問
/// 「這些還在嗎」，沒回來的標成下架，快取不刪。
void main() {
  YoutubeVideo v(String id) => YoutubeVideo(
    videoId: id,
    title: '影片 $id',
    publishedAt: DateTime(2026, 1, 1),
    thumbnailUrl: '',
  );

  test('沒回來的標下架、兩週內不重查、重新公開的拿掉標記', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    // 120 部：要分 3 批問（50＋50＋20）。
    final ids = [for (var i = 0; i < 120; i++) 'v$i'];
    await cache.upsertVideos('ch', [for (final id in ids) v(id)]);

    var gone = {'v3', 'v77', 'v110'};
    var calls = 0;
    http.Client client() => MockClient((req) async {
      calls++;
      final asked = req.url.queryParameters['id']!.split(',');
      expect(asked.length, lessThanOrEqualTo(50));
      return http.Response(
        jsonEncode({
          'items': [
            for (final id in asked)
              if (!gone.contains(id)) {'id': id},
          ],
        }),
        200,
      );
    });
    final checker = YtRemovedVideoChecker(store, const YoutubeApiService('k'));
    Future<int?> run(DateTime now) =>
        http.runWithClient(() => checker.checkIfDue('ch', now: now), client);

    final day1 = DateTime(2026, 10, 12);
    expect(await run(day1), 3);
    expect(calls, 3);
    var removed = (await cache.load('ch')).where((x) => x.removedAt != null);
    expect(removed.map((x) => x.videoId).toSet(), gone);
    expect(removed.first.removedAt, day1);

    // 兩週內：不打 API。
    expect(await run(day1.add(const Duration(days: 13))), isNull);
    expect(calls, 3);

    // 超過兩週再查：v3 重新公開、v5 新下架；v77 原本的下架時間不變。
    gone = {'v5', 'v77', 'v110'};
    final day15 = day1.add(const Duration(days: 15));
    expect(await run(day15), 1);
    final byId = {for (final x in await cache.load('ch')) x.videoId: x};
    expect(byId['v3']!.removedAt, isNull);
    expect(byId['v5']!.removedAt, day15);
    expect(byId['v77']!.removedAt, day1);
    // 快取一部都沒刪。
    expect(byId.length, 120);
  });

  test('下架標記會跟著同步帶到別台', () async {
    final store = _MemoryStore();
    final cache = YtVideoCacheStore(store);
    await cache.upsertVideos('ch', [v('a'), v('b')]);
    await cache.mergeFromCloud('ch', [
      v('a').withRemoved(DateTime(2026, 10, 1)),
    ], null);
    final byId = {for (final x in await cache.load('ch')) x.videoId: x};
    expect(byId['a']!.removedAt, DateTime(2026, 10, 1));
    expect(byId['b']!.removedAt, isNull);
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

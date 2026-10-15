import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_video_watch_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_video_watch.dart';

/// 看過紀錄存影片資料（2026-10-15）：紀錄頁直接用，不用翻頻道快取。
void main() {
  final v = YoutubeVideo(
    videoId: 'v1',
    title: '晴天',
    publishedAt: DateTime(2026, 1, 1),
    thumbnailUrl: 't',
  );

  test('點開時記下影片資料；再點一次沒帶也不會弄丟', () async {
    final s = YtVideoWatchStore(_MemoryStore());
    await s.markOpened('v1', video: v, channelId: 'UC');
    final r = await s.markOpened('v1');
    expect(r.openedAt, hasLength(2));
    expect(r.video?.title, '晴天');
    expect(r.channelId, 'UC');
    final back = (await s.loadAll())['v1']!;
    expect(back.video?.title, '晴天');
  });

  test('同步：別台有影片資料就補過來', () async {
    final s = YtVideoWatchStore(_MemoryStore());
    await s.markOpened('v1');
    final at = (await s.loadAll())['v1']!.openedAt;
    final n = await s.mergeFromCloud({
      'v1': YtVideoWatchRecord(openedAt: at, video: v, channelId: 'UC'),
    });
    expect(n, 1);
    expect((await s.loadAll())['v1']!.channelId, 'UC');
  });

  test('補齊：沒資料的從快取補，找不到的算 missing', () async {
    final s = YtVideoWatchStore(_MemoryStore());
    await s.markOpened('v1');
    await s.markOpened('v2');
    final r = await s.backfill({'v1': (video: v, channelId: 'UC')});
    expect((r.filled, r.missing), (1, 1));
    expect((await s.loadAll())['v1']!.video?.title, '晴天');
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

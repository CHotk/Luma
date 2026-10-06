import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_channel_log_store.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_channel_log_page.dart';

YtChannel _ch(String id, {String? category = 'games'}) => YtChannel(
  id: id,
  name: id,
  categoryId: category,
  youtubeChannelId: 'UC$id',
  addedAt: DateTime(2026, 9, 1),
);

void main() {
  test('加入、換分類、置頂、冷藏、改名、刪除、還原、永久刪除都會記到那個頻道的紀錄', () async {
    final store = _MemoryStore();
    final repo = YtTrackerRepository(store);
    await repo.addCategory(
      const YtCategory(id: 'games', name: '遊戲', colorValue: 0),
    );
    await repo.addCategory(
      const YtCategory(id: 'tech', name: '科技', colorValue: 0),
    );

    await repo.addChannel(_ch('a'));
    var a = (await repo.loadChannels()).single;
    await repo.updateChannel(a.copyWith(categoryId: 'tech'));
    a = (await repo.loadChannels()).single;
    await repo.updateChannel(a.copyWith(pinnedAt: DateTime.now()));
    a = (await repo.loadChannels()).single;
    await repo.updateChannel(
      a.copyWith(pinnedAt: null, coldAt: DateTime.now()),
    );
    a = (await repo.loadChannels()).single;
    await repo.updateChannel(a.copyWith(name: 'A2'));
    await repo.deleteChannel('a');
    await repo.restoreChannel('a');
    await repo.deleteChannel('a');
    await repo.purgeChannel('a');

    final events = await YtChannelLogStore(store).forChannel('a');
    expect(events.map((e) => e.type), [
      YtChannelEventType.added,
      YtChannelEventType.moved,
      YtChannelEventType.pinned,
      YtChannelEventType.unpinned,
      YtChannelEventType.cold,
      YtChannelEventType.renamed,
      YtChannelEventType.deleted,
      YtChannelEventType.restored,
      YtChannelEventType.deleted,
      YtChannelEventType.purged,
    ]);
    expect(events[0].detail['category'], '遊戲');
    expect(events[1].detail, {'from': '遊戲', 'to': '科技'});
    expect(events[5].detail, {'from': 'a', 'to': 'A2'});
  });

  test('背景訂閱數更新不算使用者操作，不記', () async {
    final store = _MemoryStore();
    final repo = YtTrackerRepository(store);
    await repo.addChannel(_ch('a'));
    final a = (await repo.loadChannels()).single;
    await repo.updateChannel(a.copyWith(subscriberCount: 1234));
    await repo.updateChannels([a.copyWith(subscriberCount: 5678)]);

    final events = await YtChannelLogStore(store).forChannel('a');
    expect(events.map((e) => e.type), [YtChannelEventType.added]);
  });

  test('刪除分類時被搬走的頻道也記一筆，註明原因', () async {
    final store = _MemoryStore();
    final repo = YtTrackerRepository(store);
    await repo.addCategory(
      const YtCategory(id: 'games', name: '遊戲', colorValue: 0),
    );
    await repo.addChannel(_ch('a'));
    await repo.deleteCategory('games');

    final moved = (await YtChannelLogStore(store).forChannel('a')).last;
    expect(moved.type, YtChannelEventType.moved);
    expect(moved.detail['to'], '未分類');
    expect(moved.detail['reason'], '分類被刪除');
  });

  test('兩台裝置的紀錄合併：依 id 去重，同一筆不會變兩筆', () async {
    final store = YtChannelLogStore(_MemoryStore());
    final e = YtChannelEvent(
      id: 'x1',
      channelId: 'a',
      at: DateTime(2026, 10, 6),
      type: YtChannelEventType.pinned,
    );
    await store.addAll([e]);
    final added = await store.mergeFromCloud([
      e,
      YtChannelEvent(
        id: 'x2',
        channelId: 'a',
        at: DateTime(2026, 10, 6, 1),
        type: YtChannelEventType.cold,
      ),
    ]);
    expect(added, 1);
    expect((await store.loadAll()).map((e) => e.id), ['x1', 'x2']);
  });

  test('時間軸：舊頻道沒有加入紀錄就用加入時間補；看影片一次點開一列；新到舊', () {
    final channel = _ch('a');
    final items = buildYtChannelLog(
      channel: channel,
      events: [
        YtChannelEvent(
          id: '1',
          channelId: 'a',
          at: DateTime(2026, 10, 6, 9),
          type: YtChannelEventType.moved,
          detail: const {'from': '遊戲', 'to': '科技'},
        ),
      ],
      watched: [
        (
          video: YoutubeVideo(
            videoId: 'v1',
            title: '第一支',
            publishedAt: DateTime(2026, 9, 10),
            thumbnailUrl: '',
          ),
          openedAt: [DateTime(2026, 9, 20), DateTime(2026, 10, 1)],
        ),
      ],
    );
    expect(items.map((i) => i.text), [
      '從「遊戲」移到「科技」',
      '看了「第一支」',
      '看了「第一支」',
      '加入',
    ]);
    expect(items.where((i) => i.isWatch), hasLength(2));
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

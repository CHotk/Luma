import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';

YtChannel _ch(String id) => YtChannel(
  id: id,
  name: id,
  categoryId: 'seed-games',
  youtubeChannelId: 'UC$id',
  addedAt: DateTime(2026, 9, 1),
);

void main() {
  // 2026-10-06 使用者：永久刪除也要留紀錄，只是不顯示；挖掘不到、同步
  // 不會跑回來；之後想加還原也不會資料遺失。
  test('永久刪除：整筆留著、垃圾桶看不到、永久刪除清單看得到，要救也救得回來', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.addChannel(_ch('a'));
    await repo.deleteChannel('a');
    expect((await repo.loadDeletedChannels()).map((c) => c.id), ['a']);

    await repo.purgeChannel('a');

    expect(await repo.loadDeletedChannels(), isEmpty);
    expect(await repo.loadChannels(), isEmpty);
    final purged = await repo.loadPurgedChannels();
    expect(purged.single.id, 'a');
    expect(purged.single.purgedAt, isNotNull);
    // 挖掘新頻道用這份比對「已知頻道」，永久刪除的還在裡面就不會被挖回來。
    expect((await repo.channelsForUpload()).map((c) => c.id), contains('a'));

    await repo.restoreChannel('a');
    final back = (await repo.loadChannels()).single;
    expect(back.deletedAt, isNull);
    expect(back.purgedAt, isNull);
    expect(back.youtubeChannelId, 'UCa');
  });

  test('永久刪除的標記會存檔、也不會被內建快照合併洗掉', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.addChannel(_ch('a'));
    await repo.deleteChannel('a');
    await repo.purgeChannel('a');

    // 內建快照裡這個頻道是活的、沒有任何刪除標記。
    await repo.mergeSeedChannels([_ch('a')]);

    expect(await repo.loadDeletedChannels(), isEmpty);
    expect((await repo.loadPurgedChannels()).single.id, 'a');

    final json = (await repo.loadPurgedChannels()).single.toJson();
    expect(YtChannel.fromJson(json).purgedAt, isNotNull);
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

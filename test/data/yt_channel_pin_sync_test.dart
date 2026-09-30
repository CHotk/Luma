// 2026-09-30 使用者回報：A 裝置把頻道置頂、調整分類順序，按同步；換
// B 裝置同步，結果 B 沒看到置頂、分類順序也沒被調整。根因是背景訂閱
// 人數自動更新（`updateChannels`）會蓋掉 `updatedAt`，讓「B 裝置剛好
// 問過一次訂閱數」贏過「A 裝置真的做了置頂這個操作」——這份測試直接
// 驗證 `updateChannels` 不會再蓋掉 `updatedAt`，以及蓋掉的話合併會出
// 什麼錯（示範用，不是真的重現雲端同步）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/seed/seed_merge.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';

void main() {
  test('updateChannels（背景訂閱人數更新）不會蓋掉 updatedAt', () async {
    final store = _MemoryStore();
    final repo = YtTrackerRepository(store);
    await repo.addChannel(
      YtChannel(
        id: 'c1',
        name: 'C',
        categoryId: null,
        addedAt: DateTime.now(),
      ).stamped(),
    );
    final beforePin = (await repo.loadChannels()).first;
    // A 裝置置頂。
    await repo.updateChannel(beforePin.copyWith(pinnedAt: DateTime(2026, 1, 1)));
    final afterPin = (await repo.loadChannels()).first;
    expect(afterPin.pinnedAt, DateTime(2026, 1, 1));
    final pinUpdatedAt = afterPin.updatedAt;

    // B 裝置（或同一台裝置背景排程）跑訂閱人數更新，這個動作不該影響
    // updatedAt，不然多裝置合併時會被誤判成「B 比較新」。
    await repo.updateChannels([afterPin.copyWith(subscriberCount: 12345)]);
    final afterStats = (await repo.loadChannels()).first;
    expect(afterStats.subscriberCount, 12345);
    expect(
      afterStats.updatedAt,
      pinUpdatedAt,
      reason: '背景訂閱人數更新不該蓋掉 updatedAt，不然會贏過別台裝置真正的編輯',
    );
    expect(afterStats.pinnedAt, DateTime(2026, 1, 1));
  });

  test('合併邏輯示範：只要 updatedAt 沒被背景更新誤蓋，置頂會正確同步過去', () {
    // 模擬 B 裝置本機版本：訂閱人數更新過，但 updatedAt 維持舊的
    // （對應上面測試驗證過的行為）。
    final bLocal = YtChannel(
      id: 'c1',
      name: 'C',
      categoryId: null,
      addedAt: DateTime(2020),
      updatedAt: DateTime(2026, 1, 1),
      subscriberCount: 12345,
    );
    // 模擬雲端版本：A 裝置置頂之後上傳的，updatedAt 比較新。
    final cloud = YtChannel(
      id: 'c1',
      name: 'C',
      categoryId: null,
      addedAt: DateTime(2020),
      updatedAt: DateTime(2026, 1, 2),
      pinnedAt: DateTime(2026, 1, 2),
    );
    final merged = mergeSeedRecords<YtChannel>(
      local: [bLocal],
      seed: [cloud],
      idOf: (c) => c.id,
      priority: SeedMergePriority.local,
      deletedAtOf: (c) => c.deletedAt,
      updatedAtOf: (c) => c.syncedAt,
    );
    expect(merged.single.pinnedAt, DateTime(2026, 1, 2));
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

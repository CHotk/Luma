// 2026-09-30 使用者回報：頻道置頂之後離開再回來就沒了，也同步不到別台。
// 根因是每次進 YT 首頁都會跑的快照合併（mergeSeedChannels）沒比
// updatedAt，快照同 id 就整筆蓋掉本機，置頂雖然被 patch 留住，
// updatedAt 卻被洗成快照的 null——同步時變成「最舊的版本」，雲端舊版
// 反過來把置頂蓋掉。這份測試用快照格式的頻道跑一輪「置頂→回首頁→同步」。
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';

void main() {
  late List<YtChannel> seed;

  // 測試用的假頻道，不是 App 的資料：這份測試只驗證「快照合併不會洗掉
  // 置頂」這段邏輯，跟真的頻道是誰無關，也不能連真的雲端（要金鑰、要網路、
  // 還會動到真資料）。原本讀打包在 App 裡的快照檔，2026-10-08 那份清空了，
  // 改成在這裡放兩筆跟快照同格式（沒有 updatedAt）的假頻道。
  setUpAll(() {
    seed = [
      for (final j in const [
        {
          'id': 'test-channel-a',
          'name': '測試頻道 A',
          'categoryId': 'test-category',
          'avatarEmoji': '📺',
          'avatarImageUrl': '',
          'url': 'https://www.youtube.com/@test-a',
          'description': '',
          'addedAt': '2026-09-22T00:00:00.000',
        },
        {
          'id': 'test-channel-b',
          'name': '測試頻道 B',
          'categoryId': 'test-category',
          'avatarEmoji': '📺',
          'avatarImageUrl': '',
          'url': 'https://www.youtube.com/@test-b',
          'description': '',
          'addedAt': '2026-09-22T00:00:00.000',
        },
      ])
        YtChannel.fromJson(j),
    ];
  });

  test('置頂後回首頁（快照合併）不會洗掉 updatedAt', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.mergeSeedChannels(seed);
    final target = (await repo.loadChannels()).first;
    await repo.updateChannel(target.copyWith(pinnedAt: DateTime.now()));
    final pinned = (await repo.loadChannels()).firstWhere(
      (c) => c.id == target.id,
    );

    await repo.mergeSeedChannels(seed);

    final after = (await repo.loadChannels()).firstWhere(
      (c) => c.id == target.id,
    );
    expect(after.pinnedAt, isNotNull);
    expect(after.updatedAt, pinned.updatedAt);
  });

  test('回首頁之後再同步，雲端的舊版（沒置頂）不會蓋掉本機置頂', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.mergeSeedChannels(seed);
    final target = (await repo.loadChannels()).first;
    // 雲端留著一份之前編輯過（有 updatedAt）但沒置頂的版本。
    final cloudOld = target.copyWith().stamped();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.updateChannel(target.copyWith(pinnedAt: DateTime.now()));

    await repo.mergeSeedChannels(seed);
    await repo.mergeChannelsFromCloud([cloudOld]);

    final after = (await repo.loadChannels()).firstWhere(
      (c) => c.id == target.id,
    );
    expect(after.pinnedAt, isNotNull);
  });

  test('冷藏後回首頁（快照合併）不會被洗掉，且存檔讀回來欄位還在', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.mergeSeedChannels(seed);
    final target = (await repo.loadChannels()).first;
    await repo.updateChannel(target.copyWith(coldAt: DateTime(2026, 10, 2)));

    await repo.mergeSeedChannels(seed);

    final after = (await repo.loadChannels()).firstWhere(
      (c) => c.id == target.id,
    );
    expect(after.coldAt, DateTime(2026, 10, 2));
    // copyWith 不帶 coldAt 時維持原樣，明確傳 null 才是移出冷藏。
    expect(after.copyWith(name: 'x').coldAt, DateTime(2026, 10, 2));
    expect(after.copyWith(coldAt: null).coldAt, isNull);
  });

  test('背景訂閱人數更新拿舊快照寫回，不會蓋掉期間做的置頂', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.mergeSeedChannels(seed);
    // 背景更新先讀了一份（還沒置頂）……
    final staleSnapshot = (await repo.channelsForUpload()).first;
    // ……打 API 的期間使用者按了置頂……
    await repo.updateChannel(staleSnapshot.copyWith(pinnedAt: DateTime.now()));
    // ……API 回來，拿舊快照寫回訂閱人數。
    await repo.updateChannels([
      staleSnapshot.copyWith(
        subscriberCount: 999,
        statsUpdatedAt: DateTime.now(),
      ),
    ]);

    final after = (await repo.loadChannels()).firstWhere(
      (c) => c.id == staleSnapshot.id,
    );
    expect(after.subscriberCount, 999);
    expect(after.pinnedAt, isNotNull);
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

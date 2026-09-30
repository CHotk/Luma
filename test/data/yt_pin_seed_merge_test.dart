// 2026-09-30 使用者回報：頻道置頂之後離開再回來就沒了，也同步不到別台。
// 根因是每次進 YT 首頁都會跑的快照合併（mergeSeedChannels）沒比
// updatedAt，快照同 id 就整筆蓋掉本機，置頂雖然被 patch 留住，
// updatedAt 卻被洗成快照的 null——同步時變成「最舊的版本」，雲端舊版
// 反過來把置頂蓋掉。這份測試用真的內建快照檔跑一輪「置頂→回首頁→同步」。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';

void main() {
  late List<YtChannel> seed;

  setUpAll(() {
    seed =
        (jsonDecode(
                  File(
                    'assets/data/yt_tracker_channels.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map<String, dynamic>>()
            .map(YtChannel.fromJson)
            .toList();
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

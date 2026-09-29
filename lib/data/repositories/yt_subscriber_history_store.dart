import 'dart:convert';

import '../../domain/models/yt_subscriber_snapshot.dart';
import '../storage/key_value_store.dart';

/// 每個頻道自己一份訂閱人數快照歷史（2026-09-29 使用者要求：不管頻道
/// 有沒有被刪除都要記，日後才有資料能畫成長曲線——YouTube API 本身沒有
/// 歷史資料，只能從現在開始自己累積，見對話紀錄的說明）。跟
/// `YtVideoCacheStore` 同一套做法：一個頻道一個 key，不塞成一份大檔。
class YtSubscriberHistoryStore {
  YtSubscriberHistoryStore(this._store);

  final KeyValueStore _store;

  static String _keyFor(String channelId) =>
      'yt_tracker.subscriber_history.$channelId.v1';

  Future<List<YtSubscriberSnapshot>> load(String channelId) async {
    final raw = await _store.read(_keyFor(channelId));
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(YtSubscriberSnapshot.fromJson)
        .toList();
  }

  /// 加一筆新快照，依時間排序存回去。不去重——同一天檢查兩次也都留著，
  /// 反正每筆很小，看得出「有檢查過」本身也是有意義的資訊。
  Future<void> add(String channelId, YtSubscriberSnapshot snapshot) async {
    final all = [...await load(channelId), snapshot]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _store.write(
      _keyFor(channelId),
      jsonEncode([for (final s in all) s.toJson()]),
    );
  }

  /// 多裝置同步用：雲端抓下來的快照跟本機的聯集合併（每個時間點各自
  /// 獨立、不會互相覆蓋，跟 log 類的紀錄同一種「只增不改」邏輯）。
  Future<int> mergeFromCloud(
    String channelId,
    List<YtSubscriberSnapshot> cloud,
  ) async {
    if (cloud.isEmpty) return 0;
    final local = await load(channelId);
    final known = {for (final s in local) '${s.at.toIso8601String()}|${s.count}'};
    final fresh = [
      for (final s in cloud)
        if (known.add('${s.at.toIso8601String()}|${s.count}')) s,
    ];
    if (fresh.isEmpty) return 0;
    final merged = [...local, ...fresh]..sort((a, b) => a.at.compareTo(b.at));
    await _store.write(
      _keyFor(channelId),
      jsonEncode([for (final s in merged) s.toJson()]),
    );
    return fresh.length;
  }
}

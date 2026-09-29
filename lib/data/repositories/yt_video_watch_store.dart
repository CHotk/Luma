import 'dart:convert';

import '../../domain/models/yt_video_watch.dart';
import '../storage/key_value_store.dart';

/// 影片「看過了嗎」的記錄，全部塞進同一個 key 的一份 map（videoId →
/// 記錄）——跟 `yt_subscriber_history_store.dart`（一個頻道一個 key）
/// 不同套路：那邊是「每個頻道自己會一直長」的歷史清單，這邊只有真的
/// 點開過的影片才會有一筆，量不會大到需要拆檔案（2026-09-29 使用者
/// 要求：點過的影片要標記、記時間戳）。
class YtVideoWatchStore {
  YtVideoWatchStore(this._store);

  final KeyValueStore _store;

  static const _key = 'yt_tracker.video_watch.v1';

  Future<Map<String, YtVideoWatchRecord>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (k, v) =>
          MapEntry(k, YtVideoWatchRecord.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<YtVideoWatchRecord?> get(String videoId) async =>
      (await loadAll())[videoId];

  Future<void> _writeAll(Map<String, YtVideoWatchRecord> all) => _store.write(
    _key,
    jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
  );

  /// 標記一支影片被點開了：第一次記下 `firstWatchedAt`，之後每次點開
  /// 只更新 `lastOpenedAt`，不會動 `firstWatchedAt`。
  Future<YtVideoWatchRecord> markOpened(String videoId) async {
    final all = await loadAll();
    final now = DateTime.now();
    final existing = all[videoId];
    final updated = YtVideoWatchRecord(
      firstWatchedAt: existing?.firstWatchedAt ?? now,
      lastOpenedAt: now,
    );
    all[videoId] = updated;
    await _writeAll(all);
    return updated;
  }

  /// 多裝置同步用：跟雲端的 map 合併，同一支影片取「較早」的
  /// `firstWatchedAt`、「較晚」的 `lastOpenedAt`——都是取極值，不管重複
  /// 同步幾次結果都一樣（不像次數用加總，那樣每同步一次就會多算）。
  Future<int> mergeFromCloud(Map<String, YtVideoWatchRecord> cloud) async {
    if (cloud.isEmpty) return 0;
    final local = await loadAll();
    var changed = 0;
    for (final entry in cloud.entries) {
      final l = local[entry.key];
      if (l == null) {
        local[entry.key] = entry.value;
        changed++;
        continue;
      }
      final merged = YtVideoWatchRecord(
        firstWatchedAt: l.firstWatchedAt.isBefore(entry.value.firstWatchedAt)
            ? l.firstWatchedAt
            : entry.value.firstWatchedAt,
        lastOpenedAt: l.lastOpenedAt.isAfter(entry.value.lastOpenedAt)
            ? l.lastOpenedAt
            : entry.value.lastOpenedAt,
      );
      if (merged.firstWatchedAt != l.firstWatchedAt ||
          merged.lastOpenedAt != l.lastOpenedAt) {
        local[entry.key] = merged;
        changed++;
      }
    }
    if (changed > 0) await _writeAll(local);
    return changed;
  }
}

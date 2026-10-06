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

  // 開啟時間戳一筆都不刪（2026-10-06 使用者糾正：這是 log，不可被清除）。
  // 原本 2026-09-30 為了減少資料量，每部影片只留最近 50 筆、更舊的直接丟掉；
  // 現在改成全部保留，「最多列 50 筆」只是開啟紀錄視窗顯示上的限制
  // （見 yt_video_row.dart 的 _showHistory）。

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

  /// 標記一支影片被點開了：每一次點開都追加一筆時間戳，不是只記第一次
  /// 跟最近一次（2026-09-29 使用者糾正：每一次都該紀錄）。
  Future<YtVideoWatchRecord> markOpened(String videoId) async {
    final all = await loadAll();
    final existing = all[videoId];
    final updated = YtVideoWatchRecord(
      openedAt: [...?existing?.openedAt, DateTime.now()],
    );
    all[videoId] = updated;
    await _writeAll(all);
    return updated;
  }

  /// 多裝置同步用：跟雲端的 map 合併，同一支影片的時間戳清單做聯集
  /// （跟 `yt_subscriber_history_store.dart` 的 [mergeFromCloud] 同一套
  /// 「只增不改」邏輯）——不是取極值蓋過去，每一次點開都是獨立事件，
  /// 兩邊都要保留。
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
      final known = {for (final t in l.openedAt) t.toUtc().toIso8601String()};
      final fresh = [
        for (final t in entry.value.openedAt)
          if (known.add(t.toUtc().toIso8601String())) t,
      ];
      if (fresh.isNotEmpty) {
        final merged = [...l.openedAt, ...fresh]..sort();
        local[entry.key] = YtVideoWatchRecord(openedAt: merged);
        changed++;
      }
    }
    if (changed > 0) await _writeAll(local);
    return changed;
  }
}

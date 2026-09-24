import 'dart:convert';

import '../../domain/models/sync_log_entry.dart';
import '../storage/key_value_store.dart';

/// 多裝置同步／備份下載的歷史紀錄，存 localStorage，跟其他 repository
/// 同一套整包讀寫的模式。
///
/// 跟 `AppLog`（`shared/debug/app_log.dart`）不一樣：那個是「剛剛發生
/// 了什麼」的除錯記憶體記錄，重新整理就清空；這個是要留著回頭查「上次
/// 同步是什麼時候、動了幾筆」的持久化紀錄（2026-09-24 使用者要求：
/// 每次同步、每次備份下載都要留 log 記錄詳情）。只留最新
/// [_maxEntries] 筆，不無限長大。
class SyncLogRepository {
  SyncLogRepository(this._store);

  static const _key = 'r2_sync.log.v1';
  static const _maxEntries = 50;

  final KeyValueStore _store;

  /// 新的在最前面，畫面列表不用自己再排一次序。
  Future<List<SyncLogEntry>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return const [];
    final list = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(SyncLogEntry.fromJson)
        .toList();
    return list..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<void> add(SyncLogEntry entry) async {
    final all = await loadAll();
    final next = [entry, ...all];
    final trimmed = next.length > _maxEntries
        ? next.sublist(0, _maxEntries)
        : next;
    await _store.write(
      _key,
      jsonEncode([for (final e in trimmed) e.toJson()]),
    );
  }

  Future<void> clear() => _store.write(_key, jsonEncode(const []));
}

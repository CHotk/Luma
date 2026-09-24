import 'dart:convert';

import '../../shared/debug/app_log.dart';
import '../storage/key_value_store.dart';

/// 除錯頁的「錯誤日誌」持久化（2026-09-24 使用者要求：錯誤日誌也是
/// log，要存雲端、不可清除）。跟 `SyncLogRepository` 同一套：只增不刪、
/// 沒有清空、沒有筆數上限，跟雲端合併就是聯集。
///
/// 只存錯誤（[AppLogEntry.isError]），一般除錯訊息量大又沒有回頭查的
/// 價值，維持只放記憶體。
class ErrorLogRepository {
  ErrorLogRepository(this._store);

  static const _key = 'debug.error_log.v1';

  final KeyValueStore _store;

  // 錯誤可能連續好幾筆同時進來，讀改寫要排隊，不然後寫的會蓋掉先寫的。
  Future<void> _queue = Future.value();

  Future<List<AppLogEntry>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(AppLogEntry.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<AppLogEntry> all) => _store.write(
    _key,
    jsonEncode([for (final e in all) e.toJson()]),
  );

  Future<void> add(AppLogEntry entry) {
    _queue = _queue.then((_) async {
      await _write([...await loadAll(), entry]);
    }).catchError((_) {});
    return _queue;
  }

  /// 把雲端的錯誤日誌併進本機（聯集），回傳新增幾筆。
  Future<int> mergeFromCloud(List<AppLogEntry> cloud) {
    final completer = _queue.then((_) async {
      final all = await loadAll();
      final known = {for (final e in all) e.identity};
      final fresh = [
        for (final e in cloud)
          if (known.add(e.identity)) e,
      ];
      if (fresh.isNotEmpty) await _write([...all, ...fresh]);
      return fresh.length;
    });
    _queue = completer.then((_) {}).catchError((_) {});
    return completer;
  }
}

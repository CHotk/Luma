import 'dart:convert';

import '../../domain/models/sync_log_entry.dart';
import '../storage/key_value_store.dart';

/// 多裝置同步／備份下載的歷史紀錄，存 localStorage，跟其他 repository
/// 同一套整包讀寫的模式。
///
/// 跟 `AppLog`（`shared/debug/app_log.dart`）不一樣：那個是「剛剛發生
/// 了什麼」的除錯記憶體記錄，重新整理就清空；這個是要留著回頭查「上次
/// 同步是什麼時候、動了幾筆」的持久化紀錄（2026-09-24 使用者要求：
/// 每次同步、每次備份下載都要留 log 記錄詳情）。
///
/// 這是 log，只增不刪：不提供清空、也不設筆數上限（2026-09-24 使用者
/// 明確要求「log 不可清除」；每筆很小，不會撐爆儲存空間）。
class SyncLogRepository {
  SyncLogRepository(this._store);

  static const _key = 'r2_sync.log.v1';

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

  /// 把雲端的紀錄併進本機，回傳新增了幾筆。log 只增不刪、不會被修改，
  /// 所以合併就是「聯集」：用時間＋動作當識別，本機沒有的才加進來，
  /// 不需要墓碑或比對更新時間（多台裝置各自的紀錄就這樣匯集成同一份）。
  Future<int> mergeFromCloud(List<SyncLogEntry> cloud) async {
    final all = await loadAll();
    final known = {for (final e in all) _identity(e)};
    final fresh = [
      for (final e in cloud)
        if (known.add(_identity(e))) e,
    ];
    if (fresh.isEmpty) return 0;
    await _store.write(
      _key,
      jsonEncode([for (final e in [...fresh, ...all]) e.toJson()]),
    );
    return fresh.length;
  }

  static String _identity(SyncLogEntry e) =>
      '${e.at.toUtc().toIso8601String()}|${e.action.name}|${e.device}';

  Future<void> add(SyncLogEntry entry) async {
    final all = await loadAll();
    await _store.write(
      _key,
      jsonEncode([for (final e in [entry, ...all]) e.toJson()]),
    );
  }
}

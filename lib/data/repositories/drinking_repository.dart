import 'dart:convert';

import '../../domain/models/drinking_entry.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 看盤／抽菸／喝酒這類「多久一次」紀錄，整包 JSON 讀寫，刪除用墓碑標記，
/// 跟 [KanaPracticeRepository] 同一套多裝置同步做法。
class DrinkingRepository {
  DrinkingRepository(this._store);

  static const _key = 'drinking.entries.v1';

  final KeyValueStore _store;

  Future<List<DrinkingEntry>> _loadAllRaw() async {
    final raw = await _store.read(_key);
    if (raw == null) return <DrinkingEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(DrinkingEntry.fromJson)
        .toList();
  }

  Future<void> _write(List<DrinkingEntry> all) =>
      _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));

  /// 給 UI 用：已刪除的濾掉，新的在前面。
  Future<List<DrinkingEntry>> loadAll() async {
    final all = (await _loadAllRaw()).where((e) => e.deletedAt == null).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return all;
  }

  /// 給同步用：連刪除標記都要看得到。
  Future<List<DrinkingEntry>> allForUpload() => _loadAllRaw();

  Future<DrinkingEntry> add({String? reason, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final entry = DrinkingEntry(
      id: now.microsecondsSinceEpoch.toString(),
      at: now,
      reason: reason,
    ).stamped();
    await _write([...await _loadAllRaw(), entry]);
    return entry;
  }

  Future<void> delete(String id) async {
    final all = await _loadAllRaw();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    all[i] = all[i].stamped(deleted: true);
    await _write(all);
  }

  /// 把 R2 雲端抓下來的紀錄併回本機，回傳實際異動幾筆。
  Future<int> mergeFromCloud(List<DrinkingEntry> incoming) async {
    if (incoming.isEmpty) return 0;
    final before = await _loadAllRaw();
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
      deletedAtOf: (e) => e.deletedAt,
      updatedAtOf: (e) => e.syncedAt,
    );
    await _write(merged);
    return ytDiffCount(
      [for (final e in before) e.toJson()],
      [for (final e in merged) e.toJson()],
    );
  }
}

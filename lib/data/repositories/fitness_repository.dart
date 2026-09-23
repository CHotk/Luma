import 'dart:convert';

import '../../domain/models/fitness.dart';
import '../storage/key_value_store.dart';

/// 健身打卡紀錄，整包 JSON blob 讀寫，跟日記／YT 頻道追蹤同一套存法。
/// 這個功能是純個人紀錄，不像 YT 頻道追蹤那樣有「專案內建種子資料」
/// 的概念，所以沒有 mergeSeed／exportJson 這兩塊。
class FitnessRepository {
  FitnessRepository(this._store);

  static const _key = 'fitness.entries.v1';

  final KeyValueStore _store;

  Future<List<FitnessEntry>> loadEntries() async {
    final raw = await _store.read(_key);
    if (raw == null) return <FitnessEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(FitnessEntry.fromJson)
        .toList();
  }

  Future<void> _write(List<FitnessEntry> all) =>
      _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));

  Future<void> addEntry(FitnessEntry entry) async {
    final all = [...await loadEntries(), entry];
    await _write(all);
  }

  Future<void> deleteEntry(String id) async {
    final all = await loadEntries()..removeWhere((e) => e.id == id);
    await _write(all);
  }
}

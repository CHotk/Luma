import 'dart:convert';

import '../../domain/models/fitness.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';

/// 健身打卡紀錄，整包 JSON blob 讀寫，跟日記／YT 頻道追蹤同一套存法，
/// 也一樣有 mergeSeed／exportJson——手機跟電腦各自打卡的紀錄存在各自
/// 瀏覽器的 localStorage，不會自動合併，要靠使用者手動匯出、貼回
/// `assets/data/fitness_entries.json` 才能讓兩邊資料同步
/// （2026-09-23 使用者要求：健身打卡也要有匯出匯入功能）。
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

  /// 編輯一筆打卡：改運動類型／時間，`id` 不變，找不到對應 `id` 就當
  /// 沒這回事——跟 [DiaryRepository.update] 同一套做法。
  Future<void> updateEntry(FitnessEntry entry) async {
    final all = await loadEntries();
    final index = all.indexWhere((e) => e.id == entry.id);
    if (index == -1) return;
    all[index] = entry;
    await _write(all);
  }

  /// 把打卡快照（見 `fitness_seed_loader.dart`）併回本機，跟
  /// [DiaryRepository.mergeSeed] 同一套邏輯（共用 `seed_merge.dart` 的
  /// [mergeSeedRecords]）。
  Future<void> mergeSeed(List<FitnessEntry> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await loadEntries(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
    );
    await _write(merged);
  }

  /// 匯出整份打卡紀錄給使用者存成真正的檔案，手動搬進 git 版控的
  /// `assets/data/fitness_entries.json`，跟日記／YT 頻道追蹤同一個用途。
  Future<({String text, int count})> exportJson() async {
    final all = await loadEntries();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in all) e.toJson()]),
      count: all.length,
    );
  }
}

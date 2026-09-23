import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;

import '../../domain/models/fitness.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';

/// 健身打卡紀錄，整包 JSON blob 讀寫，跟日記同一套存法（也一樣有
/// mergeSeed／exportJson／R2 雲端同步）。
///
/// 刪除是墓碑標記（soft delete），不是物理刪除——見
/// [FitnessEntry.deletedAt] 的說明，跟 `DiaryRepository` 同一套道理。
/// 內部所有讀寫都走 [_loadAllRaw]（含已刪除的），公開的 [loadEntries]
/// 才把已刪除的濾掉給 UI 用。
class FitnessRepository {
  FitnessRepository(this._store);

  static const _key = 'fitness.entries.v1';

  final KeyValueStore _store;

  Future<List<FitnessEntry>> _loadAllRaw() async {
    final raw = await _store.read(_key);
    if (raw == null) return <FitnessEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(FitnessEntry.fromJson)
        .toList();
  }

  Future<void> _write(List<FitnessEntry> all) =>
      _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));

  /// 給 UI 用——已刪除的濾掉，畫面不該看到鬼影資料。
  Future<List<FitnessEntry>> loadEntries() async =>
      (await _loadAllRaw()).where((e) => e.deletedAt == null).toList();

  /// 給同步用——連刪除標記都要看得到，才能正確合併、正確把刪除這件事
  /// 傳給下一台裝置或下一輪同步。
  Future<List<FitnessEntry>> loadAllIncludingDeleted() => _loadAllRaw();

  Future<void> addEntry(FitnessEntry entry) async {
    final all = [...await _loadAllRaw(), entry];
    await _write(all);
  }

  /// 刪除改標記，不是真的從清單拿掉——跟 [DiaryRepository.delete] 同一套。
  Future<void> deleteEntry(String id) async {
    final all = await _loadAllRaw();
    final index = all.indexWhere((e) => e.id == id);
    if (index == -1) return;
    all[index] = all[index].copyWithDeleted();
    await _write(all);
  }

  /// 編輯一筆打卡：改運動類型／時間，`id` 不變，找不到對應 `id` 就當
  /// 沒這回事——跟 [DiaryRepository.update] 同一套做法。
  Future<void> updateEntry(FitnessEntry entry) async {
    final all = await _loadAllRaw();
    final index = all.indexWhere((e) => e.id == entry.id);
    if (index == -1) return;
    // 蓋成現在的 updatedAt，多裝置同步要靠這個判斷「這筆最近被誰改過」。
    all[index] = entry.copyWithTouched();
    await _write(all);
  }

  /// 把打卡快照（見 `fitness_seed_loader.dart`）併回本機，跟
  /// [DiaryRepository.mergeSeed] 同一套邏輯（共用 `seed_merge.dart` 的
  /// [mergeSeedRecords]）。
  Future<void> mergeSeed(List<FitnessEntry> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await _loadAllRaw(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
      deletedAtOf: (e) => e.deletedAt,
      updatedAtOf: (e) => e.updatedAt,
    );
    await _write(merged);
  }

  /// 把 R2 雲端抓下來的打卡併回本機，跟 [DiaryRepository.mergeFromCloud]
  /// 同一套：本機贏、有刪除標記的話「刪除永遠贏」，沒刪除的話比
  /// updatedAt 新舊。回傳這次合併實際「異動」了幾筆。
  Future<int> mergeFromCloud(List<FitnessEntry> incoming) async {
    if (incoming.isEmpty) return 0;
    final before = await _loadAllRaw();
    final merged = mergeSeedRecords(
      local: before,
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.local,
      deletedAtOf: (e) => e.deletedAt,
      updatedAtOf: (e) => e.updatedAt,
    );
    await _write(merged);
    return fitnessDiffCount(before, merged);
  }

  /// 把本機現況（含刪除標記）整包覆蓋寫回 R2，跟
  /// [DiaryRepository.allForUpload] 同一套用途。
  Future<List<FitnessEntry>> allForUpload() => _loadAllRaw();

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

/// 跟 `diary_repository.dart` 的 `diaryDiffCount` 同一套比對邏輯，換成
/// 健身的 model——上傳、下載兩邊都拿這個比異動筆數。
int fitnessDiffCount(List<FitnessEntry> before, List<FitnessEntry> after) {
  final beforeById = {for (final e in before) e.id: e};
  var changed = 0;
  for (final e in after) {
    final prior = beforeById[e.id];
    if (prior == null || !mapEquals(prior.toJson(), e.toJson())) {
      changed++;
    }
  }
  return changed;
}

import 'dart:convert';

import '../../domain/models/diary_entry.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';

/// 日記的存檔紀錄，結構跟 [KanaPracticeRepository]／[KanaExamRepository]
/// 同一套：整包讀出來、整包寫回去。
class DiaryRepository {
  DiaryRepository(this._store);

  static const _key = 'diary.entries.v1';

  final KeyValueStore _store;

  Future<List<DiaryEntry>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return <DiaryEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(DiaryEntry.fromJson)
        .toList();
  }

  Future<void> add(DiaryEntry entry) async {
    final all = [...await loadAll(), entry];
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 打卡打錯了想刪掉重打，或長按列表項目刪除用。
  Future<void> delete(String id) async {
    final all = await loadAll()
      ..removeWhere((e) => e.id == id);
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 把日記快照（見 [loadDiarySeed]）併回本機，跟
  /// [KanaPracticeRepository.mergeSeed]／[KanaExamRepository.mergeSeed]
  /// 同一套邏輯（共用 `seed_merge.dart` 的 [mergeSeedRecords]）：本機
  /// 如果有跟快照同一個 `id` 的舊版本，換成快照那份，快照沒提到的 id
  /// 照樣留著。
  Future<void> mergeSeed(List<DiaryEntry> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await loadAll(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
    );
    await _store.write(_key, jsonEncode([for (final e in merged) e.toJson()]));
  }

  /// 匯出整份日記給使用者存成真正的檔案，手動搬進 git 版控的
  /// `assets/data/diary.json`，跟手寫練習／考試紀錄同一個用途——手機
  /// 跟電腦各自打卡的紀錄存在各自瀏覽器的 localStorage，不會自動合併，
  /// 只能靠使用者手動搬。
  Future<({String text, int count})> exportJson() async {
    final all = await loadAll();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in all) e.toJson()]),
      count: all.length,
    );
  }
}

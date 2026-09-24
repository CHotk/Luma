import 'dart:convert';

import '../../domain/models/kana_exam.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

/// 50 音考試的存檔紀錄。
///
/// 結構跟 [KanaPracticeRepository] 類似，但獨立儲存考試紀錄。
class KanaExamRepository {
  KanaExamRepository(this._store);

  static const _key = 'kana.exam.entries.v1';

  final KeyValueStore _store;

  /// 給 UI 用——已刪除（墓碑）的濾掉。
  Future<List<KanaExamEntry>> loadAll() async =>
      (await _loadAllRaw()).where((e) => e.deletedAt == null).toList();

  /// 給同步用——連刪除標記都要看得到。
  Future<List<KanaExamEntry>> allForUpload() => _loadAllRaw();

  Future<List<KanaExamEntry>> _loadAllRaw() async {
    final raw = await _store.read(_key);
    if (raw == null) return <KanaExamEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(KanaExamEntry.fromJson)
        .toList();
  }

  /// 新增一筆考試紀錄。
  ///
  /// 考試完成後呼叫這個，記錄使用者的手寫答案、是否正確等。
  Future<void> add(KanaExamEntry entry) async {
    final all = [...await _loadAllRaw(), entry.stamped()];
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 存在就整筆換掉（用於同一題尚未定案時的多次嘗試），不在就加新的。
  Future<void> upsert(KanaExamEntry entry) async {
    final all = await _loadAllRaw();
    final stamped = entry.stamped();
    final i = all.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      all[i] = stamped;
    } else {
      all.add(stamped);
    }
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 刪除一筆紀錄（例如清除重寫時）。
  Future<void> delete(String id) async {
    // 改標記不是真的拿掉，多裝置同步靠它才不會被別台復活。
    final all = await _loadAllRaw();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    all[i] = all[i].stamped(deleted: true);
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 清空整份考試紀錄——不可逆，呼叫端要在按鈕本身做二次確認，這裡
  /// 不重複防呆（2026-09-21 使用者要求：一鍵清空要有防呆詢問）。
  Future<void> clearAll() async {
    // 全部改標記（不是真的清空），清空這件事才會同步到別台裝置。
    final all = await _loadAllRaw();
    await _store.write(
      _key,
      jsonEncode([
        for (final e in all)
          (e.deletedAt == null ? e.stamped(deleted: true) : e).toJson(),
      ]),
    );
  }

  /// 查詢指定考試類型的所有紀錄。
  Future<List<KanaExamEntry>> findByExamType(String examType) async {
    final all = await loadAll();
    return all.where((e) => e.examType == examType).toList();
  }

  /// 統計正確率。
  Future<(int correct, int total)> getStats(String examType) async {
    final entries = await findByExamType(examType);
    if (entries.isEmpty) return (0, 0);
    final correct = entries.where((e) => e.isCorrect).length;
    return (correct, entries.length);
  }

  /// 把考試紀錄快照（見 [loadKanaExamSeed]）併回本機，跟
  /// [KanaPracticeRepository.mergeSeed] 同一套邏輯（共用
  /// `seed_merge.dart` 的 [mergeSeedRecords]）：本機如果有跟快照同一個
  /// `id` 的舊版本，換成快照那份——專案的版本為準，快照沒提到的 id，
  /// 本機原本有的照樣留著（2026-09-22 使用者要求：考試紀錄也要有這套
  /// 機制）。
  Future<void> mergeSeed(List<KanaExamEntry> incoming) async {
    if (incoming.isEmpty) return;
    final merged = mergeSeedRecords(
      local: await _loadAllRaw(),
      seed: incoming,
      idOf: (e) => e.id,
      priority: SeedMergePriority.seed,
      deletedAtOf: (e) => e.deletedAt,
    );
    await _store.write(_key, jsonEncode([for (final e in merged) e.toJson()]));
  }

  /// 把 R2 雲端抓下來的紀錄併回本機，同 [KanaPracticeRepository.mergeFromCloud]。
  Future<int> mergeFromCloud(List<KanaExamEntry> incoming) async {
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
    await _store.write(_key, jsonEncode([for (final e in merged) e.toJson()]));
    return ytDiffCount(
      [for (final e in before) e.toJson()],
      [for (final e in merged) e.toJson()],
    );
  }

  /// 匯出整份考試紀錄給使用者存成真正的檔案，跟
  /// [KanaPracticeRepository.exportJson] 同一個用途：手機跟電腦各自考
  /// 的紀錄存在各自瀏覽器的 localStorage，不會自動合併，只能靠使用者
  /// 手動搬（2026-09-21 使用者要求：考試紀錄也要能匯出）。
  Future<({String text, int count})> exportJson() async {
    final all = await loadAll();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in all) e.toJson()]),
      count: all.length,
    );
  }
}

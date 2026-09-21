import 'dart:convert';

import '../../domain/models/kana_exam.dart';
import '../storage/key_value_store.dart';

/// 50 音考試的存檔紀錄。
///
/// 結構跟 [KanaPracticeRepository] 類似，但獨立儲存考試紀錄。
class KanaExamRepository {
  KanaExamRepository(this._store);

  static const _key = 'kana.exam.entries.v1';

  final KeyValueStore _store;

  Future<List<KanaExamEntry>> loadAll() async {
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
    final all = [...await loadAll(), entry];
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 存在就整筆換掉（用於同一題尚未定案時的多次嘗試），不在就加新的。
  Future<void> upsert(KanaExamEntry entry) async {
    final all = await loadAll();
    final i = all.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      all[i] = entry;
    } else {
      all.add(entry);
    }
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 刪除一筆紀錄（例如清除重寫時）。
  Future<void> delete(String id) async {
    final all = await loadAll()
      ..removeWhere((e) => e.id == id);
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
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
}

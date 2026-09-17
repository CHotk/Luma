import 'dart:convert';

import '../../domain/models/kana_practice.dart';
import '../storage/key_value_store.dart';

/// 五十音手寫練習的存檔紀錄。
///
/// 跟 [HistoryRepository] 同一種存法：整包讀出來、整包寫回去。
/// 這裡的內容比其他紀錄檔重很多，因為圖片是 base64 字串直接塞進 JSON——
/// 量大了之後如果 localStorage 塞不下，要換成分開存或裁一個上限，
/// 現在先求能動、能留紀錄。
class KanaPracticeRepository {
  KanaPracticeRepository(this._store);

  static const _key = 'kana.practice.entries.v1';

  final KeyValueStore _store;

  Future<List<KanaPracticeEntry>> loadAll() async {
    final raw = await _store.read(_key);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(KanaPracticeEntry.fromJson)
        .toList();
  }

  Future<void> add(KanaPracticeEntry entry) async {
    final all = [...await loadAll(), entry];
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }
}

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

  /// 存在就整筆換掉，不在就當新的一筆加進去。
  ///
  /// 練習頁每畫完一筆（放手）就呼叫這個，同一個字只要沒換行／換字／
  /// 切模式，就一路用同一個 `id` 蓋掉前一版——不用等「離開這個字」
  /// 才存一次整份，寫到哪就存到哪，中途發生什麼事（分頁被關、瀏覽器
  /// 當掉）最多丟最後一筆還沒畫完的線條，不會整份不見
  /// （2026-09-17 使用者要求：不要在一堆地方各自埋存檔時機，畫一次
  /// 就存，直到做別的操作前都算同一筆）。
  Future<void> upsert(KanaPracticeEntry entry) async {
    final all = await loadAll();
    final i = all.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      all[i] = entry;
    } else {
      all.add(entry);
    }
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 「清除重寫」用：這筆之前已經靠 [upsert] 存過幾版了，使用者決定
  /// 不要這次嘗試，要連存過的也一起丟掉，不能留著半成品。
  Future<void> delete(String id) async {
    final all = await loadAll()
      ..removeWhere((e) => e.id == id);
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }
}

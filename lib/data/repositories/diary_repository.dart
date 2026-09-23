import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;

import '../../domain/models/diary_entry.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';

/// 日記的存檔紀錄，結構跟 [KanaPracticeRepository]／[KanaExamRepository]
/// 同一套：整包讀出來、整包寫回去。
///
/// 刪除是墓碑標記（soft delete），不是物理刪除——見 [DiaryEntry.deletedAt]
/// 的說明。內部所有讀寫都走 [_loadAllRaw]（含已刪除的），公開的
/// [loadAll] 才把已刪除的濾掉給 UI 用，兩者分開是為了同步合併時不能
/// 讓已刪除的標記憑空消失（見 [loadAllIncludingDeleted]）。
class DiaryRepository {
  DiaryRepository(this._store);

  static const _key = 'diary.entries.v1';

  final KeyValueStore _store;

  Future<List<DiaryEntry>> _loadAllRaw() async {
    final raw = await _store.read(_key);
    if (raw == null) return <DiaryEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(DiaryEntry.fromJson)
        .toList();
  }

  Future<void> _write(List<DiaryEntry> all) =>
      _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));

  /// 給 UI 用——已刪除的濾掉，畫面不該看到鬼影資料。
  Future<List<DiaryEntry>> loadAll() async =>
      (await _loadAllRaw()).where((e) => e.deletedAt == null).toList();

  /// 給同步／匯出用——連刪除標記都要看得到，才能正確合併、正確把
  /// 刪除這件事傳給下一台裝置或下一輪同步。
  Future<List<DiaryEntry>> loadAllIncludingDeleted() => _loadAllRaw();

  Future<void> add(DiaryEntry entry) async {
    final all = [...await _loadAllRaw(), entry];
    await _write(all);
  }

  /// 打卡打錯了想刪掉重打，或長按列表項目刪除用——標記 [DiaryEntry.deletedAt]，
  /// 不是真的從清單拿掉。
  Future<void> delete(String id) async {
    final all = await _loadAllRaw();
    final index = all.indexWhere((e) => e.id == id);
    if (index == -1) return;
    all[index] = all[index].copyWithDeleted();
    await _write(all);
  }

  /// 編輯某一篇的心情／文字，`id` 跟 `savedAt`（原始打卡時間）不變——
  /// 編輯只是改內容，不是重新打卡一次。找不到對應 `id` 就當沒這回事。
  Future<void> update(DiaryEntry entry) async {
    final all = await _loadAllRaw();
    final index = all.indexWhere((e) => e.id == entry.id);
    if (index == -1) return;
    // 蓋成現在的 updatedAt，不是照 entry 原本帶的——多裝置同步要靠這個
    // 判斷「這篇最近被誰改過」，見 [DiaryEntry.updatedAt] 的說明。
    all[index] = entry.copyWithTouched();
    await _write(all);
  }

  /// 把日記快照（見 [loadDiarySeed]）併回本機，跟
  /// [KanaPracticeRepository.mergeSeed]／[KanaExamRepository.mergeSeed]
  /// 同一套邏輯（共用 `seed_merge.dart` 的 [mergeSeedRecords]）：本機
  /// 如果有跟快照同一個 `id` 的舊版本，換成快照那份，快照沒提到的 id
  /// 照樣留著。
  Future<void> mergeSeed(List<DiaryEntry> incoming) async {
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

  /// 把 R2 雲端抓下來的日記併回本機，跟 [mergeSeed] 用同一套
  /// [mergeSeedRecords]，但 `priority` 用 [SeedMergePriority.local]
  /// 不是 `.seed`——本機這台裝置的資料贏，雲端只補本機沒有的 id；有
  /// 刪除標記的話「刪除永遠贏」（見 `seed_merge.dart` 的
  /// [mergeSeedRecords] 說明）。回傳這次合併實際「異動」了幾筆
  /// （新增／被刪除／內容有變，各算一筆），不是回傳合併後總筆數
  /// ——使用者要看到的是「這次同步做了什麼」，不是本來就有的總數
  /// （2026-09-23 使用者要求）。
  Future<int> mergeFromCloud(List<DiaryEntry> incoming) async {
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
    return diaryDiffCount(before, merged);
  }

  /// 把本機現況（含刪除標記）整包覆蓋寫回 R2——上傳不是合併，就是
  /// 單純用本機蓋掉雲端那份，理由見 `r2_sync_service.dart` 的說明。
  /// 回傳的是「這次上傳的內容」，異動筆數要呼叫端自己拿上傳前的雲端
  /// 快照跟這份比（見 [diaryDiffCount]、`r2_sync_service.dart` 的
  /// `syncDiary`）——這裡沒有「雲端原本長怎樣」可以比，不像下載那樣
  /// 本機端看得到 before/after。
  Future<List<DiaryEntry>> allForUpload() => _loadAllRaw();

  /// 匯出整份日記（不含已刪除的）給使用者存成真正的檔案，手動搬進
  /// git 版控——日記已經改用 R2 同步，這個純粹保留給想要手動備份的
  /// 情境用，不強制走這條路。
  Future<({String text, int count})> exportJson() async {
    final all = await loadAll();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in all) e.toJson()]),
      count: all.length,
    );
  }
}

/// 比較兩份日記清單多了幾筆新增、幾筆變成刪除、幾筆內容不一樣，全部
/// 加起來當「異動筆數」，每一筆不管是哪種變化都只算一次——下載
/// （[DiaryRepository.mergeFromCloud]）、上傳（`r2_sync_service.dart`
/// 的 `syncDiary`，拿上傳前的雲端快照跟即將上傳的內容比）兩邊都拿這個
/// 比，不要兩邊各寫一份幾乎一樣的邏輯（2026-09-23 使用者要求：上傳、
/// 下載的異動筆數要分開算才精確，不能只看下載那邊）。
int diaryDiffCount(List<DiaryEntry> before, List<DiaryEntry> after) {
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

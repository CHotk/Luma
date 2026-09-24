import 'dart:convert';

import '../../domain/models/kana_practice.dart';
import '../seed/seed_merge.dart';
import '../storage/key_value_store.dart';
import 'yt_tracker_repository.dart' show ytDiffCount;

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

  /// 給 UI 用——已刪除（墓碑）的濾掉。
  Future<List<KanaPracticeEntry>> loadAll() async =>
      (await _loadAllRaw()).where((e) => e.deletedAt == null).toList();

  /// 給同步用——連刪除標記都要看得到。
  Future<List<KanaPracticeEntry>> allForUpload() => _loadAllRaw();

  Future<List<KanaPracticeEntry>> _loadAllRaw() async {
    final raw = await _store.read(_key);
    // 不能回傳 `const []`：[upsert] 拿到這個列表後會直接 `.add()`
    // 進去，const 列表是不可變的，呼叫 `.add()` 會丟例外——而且是在
    // 一個沒人 await、沒人接 catchError 的 Future 裡丟，畫面上完全
    // 看不出來，唯一的症狀就是「明明畫完了，紀錄卻沒進去」。這正好
    // 是全新瀏覽器（`localStorage` 裡這個 key 從來沒寫過）第一次練習
    // 就會踩到的狀況（2026-09-18 使用者回報手機第一次寫沒進紀錄，
    // 追出來是這個）。
    if (raw == null) return <KanaPracticeEntry>[];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(KanaPracticeEntry.fromJson)
        .toList();
  }

  Future<void> add(KanaPracticeEntry entry) async {
    final all = [...await _loadAllRaw(), entry.stamped()];
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

  /// 「清除重寫」用：這筆之前已經靠 [upsert] 存過幾版了，使用者決定
  /// 不要這次嘗試，要連存過的也一起丟掉，不能留著半成品。
  Future<void> delete(String id) async {
    // 改標記不是真的拿掉，多裝置同步靠它才不會被別台復活。
    final all = await _loadAllRaw();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    all[i] = all[i].stamped(deleted: true);
    await _store.write(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  /// 把手寫紀錄快照（見 [loadKanaPracticeSeed]）併回本機。開啟練習
  /// 紀錄頁那一瞬間呼叫（見 `kana_practice_history_page.dart`）：本機
  /// 如果有跟快照同一個 `id` 的舊版本，先移除、換成快照那份——是
  /// 「專案的版本為準」，不是「本機已經有就跳過」（2026-09-18 使用者
  /// 要求：重複的去本機那邊刪掉，保留專案的）。快照沒提到的 id，
  /// 本機原本有的照樣留著，不會被清掉。
  Future<void> mergeSeed(List<KanaPracticeEntry> incoming) async {
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

  /// 把 R2 雲端抓下來的紀錄併回本機（本機贏、刪除永遠贏、其餘比更新
  /// 時間），回傳實際異動幾筆，同 `DiaryRepository.mergeFromCloud`。
  Future<int> mergeFromCloud(List<KanaPracticeEntry> incoming) async {
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

  /// 匯出整份紀錄給使用者存成真正的檔案，手動搬進 git 版控的資產裡——
  /// 跟 [HistoryRepository.exportText] 同一個用途：手機跟電腦各自練的
  /// 紀錄存在各自瀏覽器的 localStorage，不會自動合併，只能靠使用者
  /// 手動搬（2026-09-18 使用者要求）。用 JSON 陣列，不是 history.txt
  /// 那種空白分隔欄位的格式——這裡每筆紀錄都帶著巢狀的筆畫座標／
  /// 時間戳陣列，有些還有匯入圖片的 base64，塞進那種欄位格式會失真。
  Future<({String text, int count})> exportJson() async {
    final all = await loadAll();
    const encoder = JsonEncoder.withIndent('  ');
    return (
      text: encoder.convert([for (final e in all) e.toJson()]),
      count: all.length,
    );
  }
}

/// 手寫練習紀錄／考試紀錄共用的「快照合併」邏輯。凡是要把專案內建
/// 快照跟本機 localStorage 的紀錄合併，都導來呼叫 [mergeSeedRecords]，
/// 不要各自寫一份——以後要改合併規則（例如哪邊贏、要不要比時間戳
/// 新舊），一個地方找得到全部分支，不會散落在各個 repository／頁面
/// 裡各自長出稍微不一樣的版本（2026-09-22 使用者要求：寫成一個大
/// function，用參數決定走哪個 if，兩個 if 分支都用得到的部分再抽出來
/// 給這個大 function 用）。
library;

/// 同 id 衝突時要聽誰的。
enum SeedMergePriority {
  /// 專案快照贏：開啟紀錄頁那一刻把快照併回本機時用這個——同 id 的
  /// 本機那筆整筆換成快照版本（2026-09-18 使用者決定：重複的本機
  /// 刪掉，保留專案的）。
  seed,

  /// 本機贏：匯出時想「連快照一起」用這個——本機才是這台裝置剛練／
  /// 剛考的最新版本，快照只補本機沒有的那些 id。
  local,
}

/// 合併 [local] 跟 [seed] 兩份紀錄，[idOf] 取每筆的識別碼，
/// [priority] 決定同 id 衝突時誰贏。
///
/// [deletedAtOf] 選填——給有墓碑標記（soft delete）欄位的 model 用
/// （目前只有 [DiaryEntry]，見該檔案說明），不給就是舊行為，單純覆蓋
/// 不管刪除標記。有給的話合併規則是「刪除永遠贏」：任一邊只要有刪除
/// 標記，結果就是刪除，不比較時間新舊——這是 2026-09-23 使用者確認的
/// 取捨。刪除標記本身**不會**從合併結果裡濾掉，會留著繼續往下傳（給
/// 下一輪同步／下一台裝置看到這個標記），UI 該濾掉已刪除項目是呼叫端
/// 自己的事（見 `DiaryRepository.loadAll()` 濾掉、
/// `loadAllIncludingDeleted()` 保留兩個方法分開）。
///
/// [updatedAtOf] 選填——兩邊都沒有刪除標記時，用這個比新舊，新的贏
/// （2026-09-23 使用者發現：沒有這個的話，[priority] 固定某一邊贏，
/// 裝置 A 編輯過、推上雲端之後，裝置 B 沒改過的舊版反而會蓋掉 A 的
/// 編輯，等於編輯沒同步到）。不給就退回舊行為：純粹看 [priority] 那
/// 邊贏，不比時間。
List<T> mergeSeedRecords<T>({
  required List<T> local,
  required List<T> seed,
  required String Function(T) idOf,
  required SeedMergePriority priority,
  DateTime? Function(T)? deletedAtOf,
  DateTime Function(T)? updatedAtOf,
}) {
  if (seed.isEmpty) return local;

  switch (priority) {
    case SeedMergePriority.seed:
      return _overlay(
        base: local,
        overlay: seed,
        idOf: idOf,
        deletedAtOf: deletedAtOf,
        updatedAtOf: updatedAtOf,
      );
    case SeedMergePriority.local:
      return _overlay(
        base: seed,
        overlay: local,
        idOf: idOf,
        deletedAtOf: deletedAtOf,
        updatedAtOf: updatedAtOf,
      );
  }
}

/// 兩個分支都要用到的「把 overlay 疊到 base 上」，差別只在誰當
/// base、誰當 overlay，抽出來給 [mergeSeedRecords] 共用，不要兩個分支
/// 各寫一次一樣的 Map 邏輯。
List<T> _overlay<T>({
  required List<T> base,
  required List<T> overlay,
  required String Function(T) idOf,
  DateTime? Function(T)? deletedAtOf,
  DateTime Function(T)? updatedAtOf,
}) {
  final byId = {for (final e in base) idOf(e): e};
  for (final e in overlay) {
    final id = idOf(e);
    final existing = byId[id];
    if (existing == null) {
      byId[id] = e;
      continue;
    }
    final existingDeleted = deletedAtOf?.call(existing) != null;
    final incomingDeleted = deletedAtOf?.call(e) != null;
    if (existingDeleted && !incomingDeleted) {
      // base 這邊已經有刪除標記、overlay 這筆沒有，刪除贏，不覆蓋回去。
      continue;
    }
    if (incomingDeleted) {
      // overlay 這筆是刪除，刪除永遠贏，不比時間戳直接覆蓋。
      byId[id] = e;
      continue;
    }
    // 都沒有刪除標記：有給 updatedAtOf 就比新舊，base 比較新就留著；
    // 沒給就退回舊行為，overlay 直接贏。
    if (updatedAtOf != null && updatedAtOf(existing).isAfter(updatedAtOf(e))) {
      continue;
    }
    byId[id] = e;
  }
  return byId.values.toList();
}

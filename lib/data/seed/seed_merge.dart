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
List<T> mergeSeedRecords<T>({
  required List<T> local,
  required List<T> seed,
  required String Function(T) idOf,
  required SeedMergePriority priority,
}) {
  if (seed.isEmpty) return local;

  switch (priority) {
    case SeedMergePriority.seed:
      return _overlay(base: local, overlay: seed, idOf: idOf);
    case SeedMergePriority.local:
      return _overlay(base: seed, overlay: local, idOf: idOf);
  }
}

/// 兩個分支都要用到的「把 overlay 疊到 base 上」，差別只在誰當
/// base、誰當 overlay，抽出來給 [mergeSeedRecords] 共用，不要兩個分支
/// 各寫一次一樣的 Map 邏輯。
List<T> _overlay<T>({
  required List<T> base,
  required List<T> overlay,
  required String Function(T) idOf,
}) {
  final byId = {for (final e in base) idOf(e): e};
  for (final e in overlay) {
    byId[idOf(e)] = e;
  }
  return byId.values.toList();
}

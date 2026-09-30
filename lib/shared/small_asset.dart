/// 把大圖的資產路徑換成 `tool/resize_small_images.dart` 產生的縮小版
/// （同資料夾底下的 `small/`）。原圖完全沒動，使用者資料／雲端同步裡
/// 存的也還是原本的路徑（例如分類的 `imageUrl`），只有「要顯示的那一刻」
/// 才換成小圖（2026-09-30 使用者要求：另外產檔，原本的不要動）。
///
/// 不在清單裡的資料夾、網址、已經是 small/ 的路徑都原樣傳回。呼叫端要
/// 用 [Image.asset] 的 `errorBuilder` 退回原圖——之後新增的原圖如果忘了
/// 重跑腳本，就沒有對應的小圖，退回原圖顯示只是慢一點，不會壞掉。
String smallAssetFor(String path) {
  for (final dir in _dirsWithSmall) {
    if (path.startsWith(dir) && !path.startsWith('${dir}small/')) {
      final name = path.substring(dir.length);
      // 只處理資料夾正下方的檔案，子資料夾裡的（例如 yt_tracker/備用/）
      // 腳本沒有產小圖，不要換。
      if (name.contains('/')) return path;
      return '${dir}small/$name';
    }
  }
  return path;
}

/// 跟 `tool/resize_small_images.dart` 的 `_targets` 要一致，兩邊改一邊
/// 就要改另一邊。
const _dirsWithSmall = [
  'assets/images/yt_tracker/',
  'assets/images/nav_icons/',
  'assets/images/fitness/',
  'assets/images/user_profile/',
];

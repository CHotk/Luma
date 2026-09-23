// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// 直接呼叫 `window.open`，**同步**執行、不 await 任何東西。
///
/// 手機版 Safari 的彈窗封鎖只認「使用者點擊事件處理常式裡『同步』呼叫
/// 的 window.open」，只要中間夾了一個 await／microtask（`url_launcher`
/// 內部走 plugin channel 一定會夾），瀏覽器就會認定這次呼叫已經不是
/// 使用者手勢觸發的，直接擋掉——桌機瀏覽器對這條規則比較寬鬆，所以
/// 桌機測不出來，手機才會出現「打不開連結」（2026-09-23 使用者拿實機
/// 回報才抓到，桌機版之前用 `launchUrl(mode: platformDefault)` 已經
/// 修過一次未捕捉例外的問題，但手機這個是另一個更嚴格的限制）。
bool openExternalUrlSync(String url) {
  html.window.open(url, '_blank');
  return true;
}

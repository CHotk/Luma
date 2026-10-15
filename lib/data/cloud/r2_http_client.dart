// 跟 R2 講話用的 HTTP client。
//
// 網頁版要特別做一個：瀏覽器的 fetch 預設會用 HTTP 快取，R2 回應帶
// Last-Modified、沒帶 Cache-Control，瀏覽器會自己猜「這份還新鮮」直接拿
// 舊的回來（2026-10-15 使用者回報：手機抓完頻道全部影片、同步上傳了，
// 電腦同步卻幾乎沒下載，進頻道又整個重抓——電腦拿到的是之前快取的那份）。
// 同步一定要拿雲端現在的內容，所以網頁版一律不走快取。
export 'r2_http_client_stub.dart'
    if (dart.library.js_interop) 'r2_http_client_web.dart';

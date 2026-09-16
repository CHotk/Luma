// 存一個文字檔給使用者。
//
// 網頁版走瀏覽器下載，手機瀏覽器打開同一個網頁版也是走這條路
// （手機上的 Chrome/Safari 一樣支援 `<a download>`，存到「下載」或
// 「檔案」App，不需要另外裝原生 App 的外掛）。
// 回傳成不成功，呼叫端可以在失敗時退回複製剪貼簿。
//
// 用條件匯入分平台實作，不是判斷 `kIsWeb` 再 if/else：
// `dart:html` 在非網頁平台編譯不過，一定要用條件匯入才能兩邊都編譯。
export 'file_download_stub.dart' if (dart.library.html) 'file_download_web.dart';

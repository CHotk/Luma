// 依平台挑儲存後端。網頁版用 IndexedDB（容量大），其他平台照舊用
// shared_preferences。用條件匯入的理由同 `data/export/file_download.dart`：
// `dart:html` 在非網頁平台編譯不過。
export 'platform_store_stub.dart'
    if (dart.library.html) 'platform_store_web.dart';

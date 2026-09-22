// 瀏覽器通知測試用。
//
// 用條件匯入分平台實作，跟 `data/export/file_download.dart` 同一套理由：
// `dart:html` 在非網頁平台編譯不過，一定要條件匯入才能兩邊都編譯。
export 'notification_service_stub.dart'
    if (dart.library.html) 'notification_service_web.dart';

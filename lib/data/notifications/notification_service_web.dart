// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// 網頁平台專用實作，只透過 notification_service.dart 的條件匯入在網頁
// 編譯目標下才會用到，理由跟 file_download_web.dart 同一份說明。
import 'dart:html' as html;

/// 要通知權限。已經同意過就直接回 true，不會每次都重問一次。
Future<bool> requestNotificationPermission() async {
  if (!html.Notification.supported) return false;
  if (html.Notification.permission == 'granted') return true;
  final result = await html.Notification.requestPermission();
  return result == 'granted';
}

/// 送一則測試通知，給使用者確認「這個瀏覽器／裝置真的收得到通知」。
/// 目前只是單純的本機通知，不是真的推播（見 `docs/規則.md` YT 頻道
/// 追蹤一節：真的推播需要後端，這個 App 現在沒有），單純測支不支援。
Future<void> showTestNotification() async {
  if (!html.Notification.supported) return;
  if (html.Notification.permission != 'granted') {
    final granted = await requestNotificationPermission();
    if (!granted) return;
  }
  html.Notification(
    'Lume 測試通知',
    body: '收到這則就代表這個瀏覽器／裝置支援通知。',
  );
}

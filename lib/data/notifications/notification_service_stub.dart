/// 非網頁平台的預設實作。
///
/// 這個 App 目前只有網頁版真的在用，通知也只有網頁版的意義，
/// 回傳 false／直接不做事，讓呼叫端知道這個平台沒有真的送出。
Future<bool> requestNotificationPermission() async => false;

Future<void> showTestNotification() async {}

import 'package:web/web.dart' as web;

/// 用 replace，上一頁不會回到這個已經搬走的網址。
void redirectTo(String url) => web.window.location.replace(url);

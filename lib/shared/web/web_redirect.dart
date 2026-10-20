// 換到別的網址（例如搬出去的記帳 App）。網頁版才有用，其他平台什麼都不做。
export 'web_redirect_stub.dart' if (dart.library.html) 'web_redirect_web.dart';

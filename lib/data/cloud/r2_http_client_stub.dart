import 'package:http/http.dart' as http;

/// 非網頁平台：一般的 client，本來就不會自己快取。
http.Client createR2HttpClient() => http.Client();

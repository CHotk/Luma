// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// 這個檔案本來就是「網頁平台專用實作」，只透過 file_download.dart 的條件匯入
// 在網頁編譯目標下才會被用到，不是隨便在共用程式碼裡引用 dart:html。
// package:web + dart:js_interop 是官方建議的新寫法，但這裡先用最簡單、
// 已經穩定很久的 dart:html Blob 下載，之後真的要換再換。
import 'dart:convert';
import 'dart:html' as html;

/// 網頁版：用瀏覽器原生的下載機制。
///
/// 建一個看不見的 `<a download>` 連結指到記憶體裡的 Blob，點一下馬上丟掉，
/// 使用者看到的就是瀏覽器自己的「另存新檔／下載」流程，跟一般網站下載檔案一樣。
bool saveTextFile(String filename, String content) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/plain;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}

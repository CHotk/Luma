// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// 這個檔案本來就是「網頁平台專用實作」，只透過 file_download.dart 的條件匯入
// 在網頁編譯目標下才會被用到，不是隨便在共用程式碼裡引用 dart:html。
// package:web + dart:js_interop 是官方建議的新寫法，但這裡先用最簡單、
// 已經穩定很久的 dart:html Blob 下載，之後真的要換再換。
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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

/// 存一個二進位檔（例如 zip）。
bool saveBytesFile(String filename, List<int> bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}

/// 存一張圖片（2026-10-16 使用者要求「留個紀念」要真的存圖、不管作業系統）：
/// 手機瀏覽器支援分享檔案就叫系統分享選單（iPhone 選「儲存影像」進照片、
/// Android 存相簿）；不支援（電腦）或分享失敗就直接下載 PNG。
Future<bool> shareOrSaveImage(String filename, List<int> png) =>
    shareOrSaveFile(filename, png, 'image/png');

/// 存任何檔（PDF 等）：手機叫系統分享選單，電腦直接下載。
Future<bool> shareOrSaveFile(
  String filename,
  List<int> data,
  String mimeType,
) async {
  final bytes = Uint8List.fromList(data);
  final mobile = RegExp(
    'Mobi|Android|iPhone|iPad',
  ).hasMatch(web.window.navigator.userAgent);
  if (mobile) {
    final file = web.File(
      [bytes.toJS].toJS,
      filename,
      web.FilePropertyBag(type: mimeType),
    );
    final data = web.ShareData(files: [file].toJS);
    try {
      if (web.window.navigator.canShare(data)) {
        await web.window.navigator.share(data).toDart;
        return true;
      }
    } catch (_) {
      // 使用者取消、或瀏覽器不讓分享 → 退回下載。
    }
  }
  return saveBytesFile(filename, bytes, mimeType);
}

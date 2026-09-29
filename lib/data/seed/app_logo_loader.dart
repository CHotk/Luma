import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 列出 `assets/images/app_logo/` 底下打包進 App 的圖片路徑，給設定頁
/// 的「App Logo」選擇器用（2026-09-29 使用者要求：資料夾裡的圖都要能
/// 選來當 Logo，不要每加一張圖就要改一次程式）。
///
/// 靠 Flutter 建置時自動產生的 `AssetManifest.json`（記錄每個打包進去的
/// 資產路徑）動態列舉，不是寫死檔名清單——`pubspec.yaml` 裡這個資料夾
/// 是整包宣告（`assets/images/app_logo/`），加新圖片只要放進去、重新
/// build 就會自動出現在這裡，不用再改這支檔案。
Future<List<String>> loadAppLogoAssetPaths() async {
  const dir = 'assets/images/app_logo/';
  final manifestJson = await rootBundle.loadString('AssetManifest.json');
  final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
  final paths = manifest.keys.where((k) => k.startsWith(dir)).toList()..sort();
  return paths;
}

// 一次性工具腳本，不是 App 的一部分——幫幾個圖檔資料夾各產生一份縮小版
// 放在該資料夾底下的 `small/`，原圖完全不動（2026-09-30 使用者要求：
// 另外產檔、原本的不要動）。跑法：dart run tool/resize_small_images.dart
//
// 為什麼要縮：這些都是使用者準備的原始大圖（分類底圖一張 1.2~2.3MB、
// 1672x941；圖示一張 0.3~0.7MB），畫面上卻只用很小的尺寸顯示。網頁版
// 每張都要從網路下載、每次開 App 都要整張解碼才縮得下來，分類頁的底圖
// 才會「等老半天才出現」。App 顯示時透過 `lib/shared/small_asset.dart`
// 換成這裡產生的小圖路徑。
//
// 新增或換掉原圖之後要重跑一次這支腳本，不然新圖沒有對應的小圖版本
// （顯示端讀不到小圖會退回原圖，不會壞，只是又變慢）。
import 'dart:io';

import 'package:image/image.dart' as img;

// 資料夾 → 縮完之後長邊最多幾 px。
// - yt_tracker：分類卡片兩欄、寬高比 1.5，一張大約 180 邏輯 px 寬，
//   抓 3 倍給高解析度螢幕＝540，留點餘裕取 640。
// - 其他都是圖示：首頁 28px、側欄 19px、大頭貼 34px、設定／統計鈕預設
//   20px，3 倍最多約 100，取 128。
const _targets = {
  'assets/images/yt_tracker': 640,
  'assets/images/nav_icons': 128,
  'assets/images/fitness': 128,
  'assets/images/user_profile': 128,
};

void main() {
  var totalBefore = 0;
  var totalAfter = 0;
  for (final MapEntry(key: dirPath, value: maxSide) in _targets.entries) {
    final outDir = Directory('$dirPath/small')..createSync(recursive: true);
    // 只處理資料夾正下方的 PNG，不遞迴進子資料夾（像 yt_tracker/備用、
    // fitness/新增資料夾 這種使用者自己放東西的地方）。
    final sources =
        Directory(dirPath)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.png'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final src in sources) {
      final name = src.uri.pathSegments.last;
      final bytes = src.readAsBytesSync();
      final decoded = img.decodePng(bytes);
      if (decoded == null) {
        stderr.writeln('跳過（不是有效 PNG）：${src.path}');
        continue;
      }
      final longSide = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final resized = longSide <= maxSide
          ? decoded
          : decoded.width >= decoded.height
          ? img.copyResize(
              decoded,
              width: maxSide,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              decoded,
              height: maxSide,
              interpolation: img.Interpolation.average,
            );
      final out = File('${outDir.path}/$name')
        ..writeAsBytesSync(img.encodePng(resized, level: 9));
      totalBefore += bytes.length;
      totalAfter += out.lengthSync();
      stdout.writeln(
        '$dirPath/$name: ${decoded.width}x${decoded.height} '
        '(${bytes.length ~/ 1024} KB) -> ${resized.width}x${resized.height} '
        '(${out.lengthSync() ~/ 1024} KB)',
      );
    }
  }
  stdout.writeln('合計 ${totalBefore ~/ 1024} KB -> ${totalAfter ~/ 1024} KB');
}

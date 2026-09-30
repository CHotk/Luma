// 一次性工具腳本，不是 App 的一部分——產生啟動畫面專用的小尺寸 logo，
// 不動原本 assets/images/app_logo/ 底下使用者準備的原圖（那些還是設定頁
// 選圖器要用的完整解析度版本）。跑法：dart run tool/resize_splash_logo.dart
//
// 背景（2026-09-30 使用者回報）：logo02.png 是 1672x941、1.6MB 的原始
// 解析度，但啟動畫面只用 120x120 顯示。就算瀏覽器快取住這個檔案，每次
// App 冷啟動引擎重新初始化，還是要把這 1.6MB 的原始大圖整張解碼一次才能
// 縮小畫出來——這個 CPU 成本每次啟動都要重付，快取只省了下載那段，
// 省不掉解碼那段，這是啟動畫面每次都慢的真正原因。
import 'dart:io';

import 'package:image/image.dart' as img;

// 120 邏輯 px，抓 3 倍給高解析度螢幕用，四捨五入留一點餘裕。
const _targetMaxSide = 360;

const _sources = ['logo.png', 'logo02.png'];

void main() {
  final srcDir = Directory('assets/images/app_logo');
  final outDir = Directory('assets/images/app_logo/splash')
    ..createSync(recursive: true);

  for (final name in _sources) {
    final srcFile = File('${srcDir.path}/$name');
    if (!srcFile.existsSync()) {
      stderr.writeln('跳過（找不到）：${srcFile.path}');
      continue;
    }
    final bytes = srcFile.readAsBytesSync();
    final decoded = img.decodePng(bytes);
    if (decoded == null) {
      stderr.writeln('跳過（不是有效 PNG）：${srcFile.path}');
      continue;
    }
    final longSide = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final resized = longSide <= _targetMaxSide
        ? decoded
        : (decoded.width >= decoded.height
              ? img.copyResize(
                  decoded,
                  width: _targetMaxSide,
                  interpolation: img.Interpolation.average,
                )
              : img.copyResize(
                  decoded,
                  height: _targetMaxSide,
                  interpolation: img.Interpolation.average,
                ));
    final outFile = File('${outDir.path}/$name');
    outFile.writeAsBytesSync(img.encodePng(resized, level: 9));
    final beforeKb = (bytes.length / 1024).toStringAsFixed(0);
    final afterKb = (outFile.lengthSync() / 1024).toStringAsFixed(0);
    stdout.writeln(
      '$name: ${decoded.width}x${decoded.height} ($beforeKb KB) '
      '-> ${resized.width}x${resized.height} ($afterKb KB)',
    );
  }
}

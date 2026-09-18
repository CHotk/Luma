import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/kana_practice/kana_paper.dart';

void main() {
  // renderStrokesToGif 用 dart:ui 的 PictureRecorder/Canvas 畫格，
  // Picture.toImage() 是靠引擎真正的非同步回呼才會完成——testWidgets
  // 預設跑在 flutter_test 的 fake-async 時鐘裡，那種回呼永遠不會觸發，
  // 會整個卡死。要用 tester.runAsync 包起來，暫時跳出 fake-async、
  // 借真正的事件迴圈跑這段。
  testWidgets('renderStrokesToGif：輸出是合法的 GIF 檔頭', (tester) async {
    final strokes = [
      [(const Offset(0.1, 0.1), 0.0), (const Offset(0.5, 0.5), 100.0)],
      [(const Offset(0.6, 0.2), 150.0), (const Offset(0.8, 0.8), 300.0)],
    ];

    final bytes = await tester.runAsync(
      () => renderStrokesToGif(strokes, size: 32, maxFrames: 5),
    );

    expect(bytes!.length, greaterThan(0));
    // GIF 檔頭固定是 ASCII 的 "GIF89a"。
    expect(String.fromCharCodes(bytes.take(6)), 'GIF89a');
  });

  testWidgets('renderStrokesToGif：空筆畫也要能產生一張（不丟例外）', (tester) async {
    final bytes = await tester.runAsync(
      () => renderStrokesToGif(const <List<(Offset, double)>>[], size: 32),
    );

    expect(bytes!.length, greaterThan(0));
    expect(String.fromCharCodes(bytes.take(6)), 'GIF89a');
  });
}

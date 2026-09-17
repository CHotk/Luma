import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/kana_practice/kana_paper.dart';

/// 重播要重現「筆畫之間停多久」，全靠 totalDurationMs 抓對整份紀錄
/// 實際花了多久，這個算錯，AnimationController 的總時長就跟著錯。
void main() {
  test('totalDurationMs 取最後一筆最後一個點的時間戳', () {
    final strokes = <List<TimedPoint>>[
      [(const Offset(0, 0), 0.0), (const Offset(1, 1), 120.0)],
      [(const Offset(2, 2), 400.0), (const Offset(3, 3), 900.0)],
    ];
    expect(ReplayInkPainter.totalDurationMs(strokes), 900.0);
  });

  test('totalDurationMs 空紀錄回傳 0', () {
    expect(ReplayInkPainter.totalDurationMs(const []), 0);
  });

  test('totalDurationMs 略過結尾的空筆畫，不會誤判成 0', () {
    final strokes = <List<TimedPoint>>[
      [(const Offset(0, 0), 0.0), (const Offset(1, 1), 300.0)],
      <TimedPoint>[],
    ];
    expect(ReplayInkPainter.totalDurationMs(strokes), 300.0);
  });
}

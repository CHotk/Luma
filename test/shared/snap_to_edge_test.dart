import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/snap_to_edge.dart';

/// 回到最上面可以拖，放開像 iPhone 小圓點：2026-10-15 改成只吸左右，
/// 上下放哪就停哪，但離底部至少一段距離。
void main() {
  // 容器：按鈕離右邊最多 300、離下面最多 600；底部至少留 100。
  Offset snap(double right, double bottom) => snapToNearestEdge(
    Offset(right, bottom),
    maxRight: 300,
    maxBottom: 600,
    minBottom: 100,
  );

  test('靠右邊放開：貼右邊，高度不變', () {
    expect(snap(40, 250), const Offset(10, 250));
  });

  test('靠左邊放開：貼左邊', () {
    expect(snap(280, 250), const Offset(290, 250));
  });

  test('靠下面放開：不會吸到底部，只往左右吸，而且離底部至少 100', () {
    expect(snap(150, 20), const Offset(10, 100));
  });

  test('靠上面放開：不會吸到頂部，停在放開的高度（不出界）', () {
    expect(snap(160, 560), const Offset(290, 560));
    expect(snap(160, 650), const Offset(290, 590));
  });
}

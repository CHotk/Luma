import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/snap_to_edge.dart';

/// 2026-10-12 使用者要求：回到最上面可以拖，放開像 iPhone 小圓點磁吸四邊。
void main() {
  // 容器：按鈕離右邊最多 300、離下面最多 600。
  Offset snap(double right, double bottom) =>
      snapToNearestEdge(Offset(right, bottom), maxRight: 300, maxBottom: 600);

  test('靠右邊放開：貼右邊，高度不變', () {
    expect(snap(40, 250), const Offset(10, 250));
  });

  test('靠左邊放開：貼左邊', () {
    expect(snap(280, 250), const Offset(290, 250));
  });

  test('靠下面放開：貼下面', () {
    expect(snap(150, 20), const Offset(150, 10));
  });

  test('靠上面放開：貼上面', () {
    expect(snap(150, 590), const Offset(150, 590));
  });

  test('角落：另一個方向也不會貼死在邊外', () {
    expect(snap(2, 1), const Offset(10, 10));
  });
}

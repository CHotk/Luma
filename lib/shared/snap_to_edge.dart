import 'dart:ui';

/// 浮動按鈕放開後吸到左邊或右邊（像 iPhone 輔助觸控小圓點）。
///
/// 2026-10-12 原本磁吸四邊；2026-10-15 使用者要求改成跟 iOS 一樣：
/// **只往左右吸**，上下放在哪就停在哪（手動拖上拖下照樣可以），只是不能
/// 超出 [minBottom]／[minTop]——底部要離遠一點，不要貼在最下面。
///
/// 位置用「離右邊、離下面多遠」表示：[p].dx＝離右邊、[p].dy＝離下面；
/// [maxRight]／[maxBottom] 是這兩個值最大能到多少（容器大小減按鈕大小）。
Offset snapToNearestEdge(
  Offset p, {
  required double maxRight,
  required double maxBottom,
  double margin = 10,
  double minBottom = 10,
  double minTop = 10,
}) {
  final right = p.dx;
  final left = maxRight - right;
  final x = right <= left ? margin : maxRight - margin;
  final hi = maxBottom - minTop;
  final y = p.dy.clamp(minBottom, hi < minBottom ? minBottom : hi);
  return Offset(x, y);
}

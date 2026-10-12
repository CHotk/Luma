import 'dart:ui';

/// 浮動按鈕放開後吸到最近的那一邊（2026-10-12 使用者要求：像 iPhone
/// 輔助觸控小圓點，磁吸四邊）。
///
/// 位置用「離右邊、離下面多遠」表示：[p].dx＝離右邊、[p].dy＝離下面；
/// [maxRight]／[maxBottom] 是這兩個值最大能到多少（容器大小減按鈕大小）。
/// 吸到哪一邊那個方向就貼在 [margin]，另一個方向留在原處、但不出界。
Offset snapToNearestEdge(
  Offset p, {
  required double maxRight,
  required double maxBottom,
  double margin = 10,
}) {
  final right = p.dx, bottom = p.dy;
  final left = maxRight - right, top = maxBottom - bottom;
  final nearest = [right, left, bottom, top].reduce((a, b) => a < b ? a : b);
  double inside(double v, double max) =>
      v.clamp(margin, max - margin < margin ? margin : max - margin);
  if (nearest == right) return Offset(margin, inside(bottom, maxBottom));
  if (nearest == left) {
    return Offset(maxRight - margin, inside(bottom, maxBottom));
  }
  if (nearest == bottom) return Offset(inside(right, maxRight), margin);
  return Offset(inside(right, maxRight), maxBottom - margin);
}

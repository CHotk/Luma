import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// Lume 的標誌：字母 L 拆成兩筆。
///
/// 直的一筆從白漸層到紫，橫的一筆是半透明淺藍。
/// 這是定案的方向 D 配色 10，要改請先看 app-spec.md 第十節。
class LumeMark extends StatelessWidget {
  const LumeMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  /// 以 100 x 100 的座標系設計，畫的時候依實際大小等比縮放。
  static const _design = 100.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _design;
    canvas.scale(k);

    final stem = RRect.fromRectAndRadius(
      const Rect.fromLTWH(33, 22, 11, 45.5),
      const Radius.circular(5.5),
    );
    canvas.drawRRect(
      stem,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.markTop, AppColors.markBottom],
        ).createShader(const Rect.fromLTWH(33, 22, 11, 45.5)),
    );

    final arm = RRect.fromRectAndRadius(
      const Rect.fromLTWH(33, 56.5, 35, 11),
      const Radius.circular(5.5),
    );
    canvas.drawRRect(arm, Paint()..color = AppColors.markArm);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 背景那幾團模糊的光。
///
/// 深色底加上這幾團色塊，毛玻璃才看得出邊緣的那道亮線。
/// 少了它整支 App 會變成一片死黑。
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: [
          const Positioned(
            left: -70,
            top: -50,
            child: _Blob(size: 260, color: AppColors.ambBlue),
          ),
          const Positioned(
            right: -80,
            top: 150,
            child: _Blob(size: 230, color: AppColors.ambEmber),
          ),
          const Positioned(
            left: -50,
            bottom: -90,
            child: _Blob(size: 280, color: AppColors.ambViolet),
          ),
          const Positioned(
            right: -45,
            bottom: 60,
            child: _Blob(size: 190, color: AppColors.ambTeal),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // 用 ImageFiltered 而不是疊一堆半透明圓，效能比較穩。
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.52),
        ),
      ),
    );
  }
}

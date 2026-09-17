import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 背景那幾團模糊的光。
///
/// 深色底加上這幾團色塊，毛玻璃才看得出邊緣的那道亮線。
/// 少了它整支 App 會變成一片死黑。
///
/// [background]／[blobColors] 可以換掉，給不同語言軌道用不同色系
/// （例如日文軌道的櫻配色）——預設值就是原本英文軌道那組，換色系
/// 只是換參數，不用整個重刻一份，四團色塊的位置/大小是固定的版面，
/// 跟色系無關。
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.background = AppColors.bg,
    this.blobColors = const [
      AppColors.ambBlue,
      AppColors.ambEmber,
      AppColors.ambViolet,
      AppColors.ambTeal,
    ],
  }) : assert(blobColors.length == 4, '固定四團色塊，換色系也要給滿四個顏色');

  final Widget child;
  final Color background;
  final List<Color> blobColors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Stack(
        children: [
          Positioned(
            left: -70,
            top: -50,
            child: _Blob(size: 260, color: blobColors[0]),
          ),
          Positioned(
            right: -80,
            top: 150,
            child: _Blob(size: 230, color: blobColors[1]),
          ),
          Positioned(
            left: -50,
            bottom: -90,
            child: _Blob(size: 280, color: blobColors[2]),
          ),
          Positioned(
            right: -45,
            bottom: 60,
            child: _Blob(size: 190, color: blobColors[3]),
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

import 'dart:ui';

import 'package:flutter/material.dart';

/// 隱私馬賽克——[masked] 為 true 時，把文字的成品畫面直接模糊掉（用
/// [ImageFiltered]，模糊的是渲染出來的像素，不是換成假文字），不是
/// 退而求其次的 `***` 那種（2026-09-23 使用者要求：日記可以一鍵把
/// 最近的文字馬賽克起來，「馬賽克比較帥，難做的話就改***」——實際
/// 做起來難度差不多，直接做真的模糊）。
class MaskedText extends StatelessWidget {
  const MaskedText(
    this.text, {
    super.key,
    required this.masked,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final bool masked;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
    if (!masked) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: 7,
        sigmaY: 7,
        tileMode: TileMode.decal,
      ),
      child: child,
    );
  }
}

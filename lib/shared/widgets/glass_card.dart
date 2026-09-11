import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';

/// 毛玻璃面板。全專案唯一的實作，不要在別處自己刻。
///
/// 三個要素缺一不可：背後的模糊、半透明的填色、上緣那道亮線。
/// 少了亮線就只是一塊灰底，玻璃感會消失。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    this.radius = Radii.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final card = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: shape,
            border: Border.all(color: AppColors.glassEdge),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: shape, child: card);
  }
}

/// 面板上方那行小標。全大寫加寬字距，只放短詞。
class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 1.2,
        color: AppColors.ink2,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

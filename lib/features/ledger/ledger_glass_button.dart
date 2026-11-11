import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 記一筆表單裡每個欄位右邊的小按鈕（時間的「不確定」、金額的「＋／−」、商家的下拉）。
///
/// 2026-11-11 使用者：每個欄位右邊都放一顆、樣式統一照「不確定」那樣，再更 iOS 26 毛玻璃一點。
/// 半透明＋模糊背景＋細白邊＋上亮下暗的漸層；開啟時帶一點顏色。高度跟輸入框一樣。
class LedgerGlassButton extends StatelessWidget {
  const LedgerGlassButton({
    super.key,
    required this.child,
    required this.onTap,
    this.selected = false,
    this.tint = const Color(0xFF5FE0A8),
    this.width,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// 開著（例如「不確定」打開、金額切到「＋」）：帶 [tint] 的顏色。
  final bool selected;
  final Color tint;
  final double? width;
  final String? tooltip;

  /// 跟輸入框同高（輸入框：字 16 號＋上下各 13 的間距＋邊框）。
  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final btn = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: selected
                    ? [tint.withValues(alpha: .38), tint.withValues(alpha: .18)]
                    : [
                        Colors.white.withValues(alpha: .16),
                        Colors.white.withValues(alpha: .05),
                      ],
              ),
              border: Border.all(
                color: selected
                    ? tint.withValues(alpha: .75)
                    : Colors.white.withValues(alpha: .20),
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.ink,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(
                        size: 20,
                        color: selected ? Colors.white : AppColors.ink2,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

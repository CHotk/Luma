import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 毛玻璃下拉選單的一個選項。
class GlassMenuItem<T> {
  const GlassMenuItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 從某個按鈕下面跳出的毛玻璃小選單（2026-10-15 使用者要求排序選單用
/// 毛玻璃）。[anchorContext] 是按鈕自己的 context，選單對齊它的右邊、
/// 出現在它下面。選了回傳那個值，點外面回傳 null。
Future<T?> showGlassMenu<T>(
  BuildContext anchorContext, {
  required List<GlassMenuItem<T>> items,
  T? selected,
  double width = 200,
}) {
  final box = anchorContext.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<T>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: '關閉選單',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, _) {
      final screen = MediaQuery.sizeOf(context);
      final left = (anchor.right - width)
          .clamp(8.0, math.max(8.0, screen.width - width - 8))
          .toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: anchor.bottom + 6,
            width: width,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Material(
                  color: const Color(0xFF1E1E2C).withValues(alpha: 0.72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items)
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.of(context).pop(item.value),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: item.value == selected
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                children: [
                                  if (item.icon != null) ...[
                                    Icon(
                                      item.icon,
                                      size: 17,
                                      color: AppColors.ink2,
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: item.value == selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  if (item.value == selected)
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 17,
                                      color: AppColors.accent,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

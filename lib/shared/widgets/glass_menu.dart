import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 毛玻璃下拉選單的一個選項。
class GlassMenuItem<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.header = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// true＝只是一行小標題（不能點），用來把選項分段。
  final bool header;
}

/// 從某個按鈕下面跳出的毛玻璃小選單（2026-10-15 使用者要求排序選單用
/// 毛玻璃）。[anchorContext] 是按鈕自己的 context，選單對齊它的右邊、
/// 出現在它下面。選了回傳那個值，點外面回傳 null。
Future<T?> showGlassMenu<T>(
  BuildContext anchorContext, {
  required List<GlassMenuItem<T>> items,
  T? selected,
  double width = 200,

  /// 多選時要打勾的那幾個值（單選用 [selected]）。
  Set<T> selectedValues = const {},

  /// 選項很多時限制選單高度、裡面可以捲動。
  double? maxHeight,

  /// true＝選單對齊按鈕左邊（預設對齊右邊）。
  bool alignLeft = false,
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
      final left = ((alignLeft ? anchor.left : anchor.right - width))
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: maxHeight ?? double.infinity,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final item in items)
                              if (item.header)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    10,
                                    4,
                                  ),
                                  child: Text(
                                    item.label,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink3,
                                    ),
                                  ),
                                )
                              else
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () =>
                                      Navigator.of(context).pop(item.value),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color:
                                          (item.value == selected ||
                                              selectedValues.contains(
                                                item.value,
                                              ))
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
                                              fontWeight:
                                                  (item.value == selected ||
                                                      selectedValues.contains(
                                                        item.value,
                                                      ))
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                        ),
                                        if (item.value == selected ||
                                            selectedValues.contains(item.value))
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
            ),
          ),
        ],
      );
    },
  );
}

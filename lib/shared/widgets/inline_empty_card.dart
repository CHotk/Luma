import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';

/// 空狀態卡片的一顆快速動作（例如「顯示已看過」「重新整理」）。
class EmptyAction {
  const EmptyAction(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

/// 全 App 共用的空狀態：清單裡放一張虛線框卡片，一句標題、一句原因，
/// 下面幾顆快速切換（2026-10-02 使用者從五種風格裡選了第 5 版「先顯示
/// 舊的、背景更新」，見 `design-history/2026-10-02_空狀態與載入中五種
/// 風格.html`）。取代原本畫面正中央一行灰字——那種寫法沒說原因、也沒
/// 告訴人怎麼辦，常被當成壞掉（例如「隱藏已看過」把影片收光的時候）。
///
/// 卡片本身不撐滿高度、也不置中整個畫面，放在清單原本該出現內容的位置，
/// 版面不會整片空白。[actions] 給空的就只有文字。
class InlineEmptyCard extends StatelessWidget {
  const InlineEmptyCard({
    super.key,
    required this.title,
    this.message,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final List<EmptyAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: CustomPaint(
        painter: const _DashedBorderPainter(
          color: AppColors.glassEdge,
          radius: 14,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 4),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppText.note,
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in actions)
                      Material(
                        color: AppColors.accentSolid.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(Radii.chip),
                        child: InkWell(
                          onTap: a.onTap,
                          borderRadius: BorderRadius.circular(Radii.chip),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 7,
                            ),
                            child: Text(
                              a.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.75),
      );
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

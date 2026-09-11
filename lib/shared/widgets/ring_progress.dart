import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 首頁的進度環。版型 04 的主角。
///
/// 環代表的是「今天的份量」，不是學習總進度。
/// 這個分別很重要：它要讓人覺得做完就可以休息，而不是永遠還差很多。
class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.done,
    required this.total,
    required this.centerLabel,
    required this.bottomLabel,
    this.size = 186,
  });

  final int done;
  final int total;

  /// 環中央那行字，通常是「1/5」。
  final String centerLabel;

  /// 環中央下方的小字，通常是時間用量。
  final String bottomLabel;

  final double size;

  @override
  Widget build(BuildContext context) {
    final full = total <= 0 || done >= total;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: total <= 0 ? 0 : (done / total).clamp(0.0, 1.0),
          // 做滿之後環會變綠，這是「今天夠了」的第一個訊號。
          color: full ? AppColors.ok : AppColors.accent,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '今天的輪數',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
              ),
              const SizedBox(height: 6),
              Text(
                bottomLabel,
                style: const TextStyle(fontSize: 11.5, color: AppColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.ink.withValues(alpha: 0.13),
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // 從十二點鐘方向開始
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

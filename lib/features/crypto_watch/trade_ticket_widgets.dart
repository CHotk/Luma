import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/trade_entry.dart';
import 'trade_ui.dart';

// 持倉中跟過去紀錄長得完全不一樣（2026-10-14 使用者選設計稿第 3 版「亮卡
// vs 票根」，再加第 4 版持倉中甘特條的流動斜紋，但不分兩組）：
// - 持倉中＝亮黃漸層卡、會呼吸的黃點、實心「平倉」鈕（[OpenTradeCard]）。
// - 點到的過去紀錄＝虛線框的灰色票根、斜蓋損益章（[TradeReceipt]），
//   長在甘特圖卡片裡面。
// - 甘特圖上持倉中的條是一直往右流的黃色斜紋（[FlowingStripes]）。

/// 甘特圖持倉中那條：像水流一樣慢慢往右流（兩層水波＋一道柔光掃過＋
/// 右端呼吸光點），一眼看出「還在進行」（2026-10-14 使用者要求：更有流動感、
/// 像水流、精美、緩慢）。
class FlowingStripes extends StatefulWidget {
  const FlowingStripes({super.key, this.radius = 6});

  final double radius;

  @override
  State<FlowingStripes> createState() => _FlowingStripesState();
}

class _FlowingStripesState extends State<FlowingStripes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _StripesPainter(_c),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  _StripesPainter(this.t) : super(repaint: t);

  /// 0→1 一圈（[FlowingStripes] 6 秒一圈），所有動作都是整數倍，接得無縫。
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final v = t.value;
    final rect = Offset.zero & size;
    // 底：左淡右濃，越接近「現在」越亮。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.mid.withValues(alpha: 0.24),
            AppColors.mid.withValues(alpha: 0.42),
          ],
        ).createShader(rect),
    );
    // 兩層水波往右慢慢流，速度、波長不一樣，疊起來像水面。
    void wave(double length, double amp, double base, int speed, double a) {
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w + 1; x += 1.5) {
        final y = base + amp * math.sin(2 * math.pi * (x / length - v * speed));
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = AppColors.mid.withValues(alpha: a),
      );
    }

    wave(46, h * 0.16, h * 0.42, 1, 0.32);
    wave(29, h * 0.12, h * 0.58, 2, 0.4);
    // 一道柔光從左往右掃過（一圈掃兩次）。
    final band = math.max(36.0, w * 0.35);
    final x = ((v * 2) % 1) * (w + band * 2) - band;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(x - band / 2, 0, band, h)),
    );
    // 上緣一條細細的反光。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, 1),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    // 右端（今天）一顆會慢慢呼吸的光點。
    final glow = 0.45 + 0.35 * math.sin(2 * math.pi * v * 3);
    canvas.drawCircle(
      Offset(w - h / 2, h / 2),
      h * 0.32,
      Paint()
        ..color = AppColors.mid.withValues(alpha: glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}

/// 會呼吸的黃點（持倉中）。
class BreathingDot extends StatefulWidget {
  const BreathingDot({super.key, this.size = 8});

  final double size;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final v = Curves.easeOut.transform((_c.value / 0.7).clamp(0.0, 1.0));
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: AppColors.mid,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.mid.withValues(alpha: 0.6 * (1 - v)),
                spreadRadius: 7 * v,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 「持倉中」區的卡：亮黃漸層、呼吸黃點、右邊實心「平倉」。
class OpenTradeCard extends StatelessWidget {
  const OpenTradeCard({
    super.key,
    required this.trade,
    required this.onTap,
    this.highlighted = false,
  });

  final TradeEntry trade;
  final VoidCallback onTap;

  /// 甘特圖上點了這一單：邊框加粗亮一下，知道是哪張。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = trade;
    final hold = DateTime.now().difference(t.openedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.mid.withValues(alpha: highlighted ? 0.28 : 0.18),
                  AppColors.mid.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(
                color: AppColors.mid.withValues(alpha: highlighted ? 0.9 : 0.5),
                width: highlighted ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BreathingDot(),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        t.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    directionLabel(t.isLong),
                    const SizedBox(width: 6),
                    LeverageBadge(t.leverage),
                    const Spacer(),
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.mid,
                        foregroundColor: const Color(0xFF1A1405),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      child: const Text('平倉'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    text: '已持倉 ',
                    children: [
                      TextSpan(
                        text: fmtHold(hold),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.mid,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
                const SizedBox(height: 2),
                Text(
                  '本金 ${fmtAmount(t.margin)}・倉位 ${fmtAmount(t.positionSize)}'
                  '・${fmtDay(t.openedAt)} ${fmtHm(t.openedAt)} 開'
                  '${t.note == null ? '' : '・${t.note}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.note.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 甘特圖上點到的已平倉紀錄：虛線框的「票根」，灰灰淡淡、斜蓋一個綠／紅
/// 損益章，一次列清楚整單；右上 ✕ 收起。
class TradeReceipt extends ConsumerWidget {
  const TradeReceipt({
    super.key,
    required this.trade,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
  });

  final TradeEntry trade;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = trade;
    final pnl = t.pnl ?? 0;
    final color = pnlColor(pnl);
    final rate = ref.watch(usdtTwdRateProvider);
    Widget line(String k, String v, {Color? valueColor}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D42))),
      ),
      child: Row(
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '🧾 已平倉的紀錄・只是看',
                      style: AppText.note.copyWith(color: AppColors.ink3),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(99),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      t.symbol,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    directionLabel(t.isLong),
                    const SizedBox(width: 6),
                    LeverageBadge(t.leverage),
                  ],
                ),
                const SizedBox(height: 6),
                line('開倉', '${fmtDay(t.openedAt)} ${fmtHm(t.openedAt)}'),
                if (t.closedAt != null) ...[
                  line('平倉', '${fmtDay(t.closedAt!)} ${fmtHm(t.closedAt!)}'),
                  line('持倉', fmtHold(t.closedAt!.difference(t.openedAt))),
                ],
                line(
                  '本金／倉位',
                  '${fmtAmount(t.margin)} / ${fmtAmount(t.positionSize)}',
                ),
                line(
                  '報酬',
                  '${fmtPct(t.pnlPercent ?? 0)}・${fmtTwd(pnl, rate, signed: true)}',
                  valueColor: color,
                ),
                if (t.note != null) line('筆記', t.note!),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEdit,
                        child: const Text('編輯'),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.bad,
                          side: BorderSide(
                            color: AppColors.bad.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text('刪除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // 斜蓋的損益章。
            Positioned(
              right: 4,
              top: 26,
              child: Transform.rotate(
                angle: -8 * math.pi / 180,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    fmtPnl(pnl),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    ).deflate(0.75);
    final paint = Paint()
      ..color = const Color(0xFF3D3D55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => false;
}

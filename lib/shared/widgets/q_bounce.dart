import 'package:flutter/material.dart';

/// 「Q 彈一下」：先縮一點、彈過頭、再回正（2026-10-12 使用者要求：首頁
/// 功能方塊點了、YT 頻道卡片長按或點 ⋮ 時都要 Q 彈一下）。
///
/// 包在要彈的東西外面，要彈的時候從底下的 context 呼叫
/// `QBounce.maybeOf(context)?.play()`。
class QBounce extends StatefulWidget {
  const QBounce({super.key, required this.child});

  final Widget child;

  /// 一次彈完要多久。首頁點方塊會等彈到一半多再換頁，見 [settleDelay]。
  static const duration = Duration(milliseconds: 420);

  /// 點了之後等多久再換頁，彈的樣子才看得到（換頁太快就看不到了）。
  static const settleDelay = Duration(milliseconds: 200);

  static QBounceState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<QBounceState>();

  @override
  State<QBounce> createState() => QBounceState();
}

class QBounceState extends State<QBounce> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: QBounce.duration,
  );

  // 1 → 0.92（按下去）→ 1.05（彈過頭）→ 0.99 → 1。
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 0.92,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.92,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.05,
        end: 0.99,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 25,
    ),
    TweenSequenceItem(tween: Tween<double>(begin: 0.99, end: 1), weight: 20),
  ]).animate(_ctrl);

  void play() => _ctrl.forward(from: 0);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

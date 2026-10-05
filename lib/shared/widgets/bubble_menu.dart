import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 泡泡橫列選單的一個動作。[destructive] 為 true 的（刪除這類）一律排在
/// 最右邊、前面自動加一條分隔線、圖示跟字用紅色。
class BubbleMenuItem<T> {
  const BubbleMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.iconColor,
    this.destructive = false,
  });

  final T value;
  final IconData icon;
  final String label;
  final Color? iconColor;
  final bool destructive;
}

/// 全 App 統一的長按操作選單：LINE／微信長按聊天訊息那種「泡泡橫列」——
/// 一條黑色泡泡浮在被按的卡片上方，圖示在上、短字在下橫向排開，小尖角
/// 指向那張卡片；刪除放最右邊、用分隔線隔開。2026-10-02 使用者從
/// `design-history/已選擇完成/2026-10-02_頻道長按選單五種風格.html` 挑了這一版，要求
/// 整個專案的長按選單都改成這個，不要在個別頁面再自己組 `showMenu` 或
/// 從底部滑出的操作面板。
///
/// [anchor] 是被按那張卡片在螢幕上的範圍（用 [bubbleAnchorOf] 從卡片的
/// context 算）。上方空間不夠時改放在卡片下方、尖角朝上。點泡泡外面或
/// 按返回鍵關閉，回傳 null。
Future<T?> showBubbleMenu<T>(
  BuildContext context, {
  required Rect anchor,
  required List<BubbleMenuItem<T>> items,
}) {
  final normal = items.where((e) => !e.destructive).toList();
  final danger = items.where((e) => e.destructive).toList();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '關閉選單',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, _) => _BubbleMenuLayout<T>(
      animation: animation,
      anchor: anchor,
      normal: normal,
      danger: danger,
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// 從卡片自己的 context 算出它在螢幕上的範圍，給 [showBubbleMenu] 的
/// `anchor` 用。
Rect bubbleAnchorOf(BuildContext cardContext) {
  final box = cardContext.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

const double _itemWidth = 58;
const double _itemHeight = 56;
const double _padding = 5;
const double _dividerWidth = 9;
const double _arrowHeight = 7;
const double _gap = 6;
const double _screenMargin = 8;
const Color _bubbleColor = Color(0xF20E0E14);

class _BubbleMenuLayout<T> extends StatelessWidget {
  const _BubbleMenuLayout({
    required this.animation,
    required this.anchor,
    required this.normal,
    required this.danger,
  });

  final Animation<double> animation;
  final Rect anchor;
  final List<BubbleMenuItem<T>> normal;
  final List<BubbleMenuItem<T>> danger;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final hasDivider = normal.isNotEmpty && danger.isNotEmpty;
    final width =
        (normal.length + danger.length) * _itemWidth +
        (hasDivider ? _dividerWidth : 0) +
        _padding * 2;
    const height = _itemHeight + _padding * 2;

    // 優先放卡片上方；上方放不下（扣掉狀態列）才放下方。
    final topLimit = media.padding.top + _screenMargin;
    final aboveTop = anchor.top - _gap - _arrowHeight - height;
    final placeAbove = aboveTop >= topLimit;
    // 尖角畫在泡泡外面（上方時在底下、下方時在頂上），所以要多讓出尖角
    // 的高度，尖端才會剛好停在離卡片 [_gap] 的位置。
    final top = placeAbove ? aboveTop : anchor.bottom + _gap + _arrowHeight;
    final left = (anchor.center.dx - width / 2)
        .clamp(
          _screenMargin,
          math.max(_screenMargin, screen.width - width - _screenMargin),
        )
        .toDouble();
    // 尖角對準卡片中心，但不能跑出泡泡的圓角範圍。
    final arrowX = (anchor.center.dx - left).clamp(18.0, width - 18.0);

    Widget cell(BubbleMenuItem<T> item) {
      final color = item.destructive
          ? AppColors.bad
          : (item.iconColor ?? AppColors.ink);
      return SizedBox(
        width: _itemWidth,
        height: _itemHeight,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).pop(item.value),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 20, color: color),
              const SizedBox(height: 5),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: item.destructive ? AppColors.bad : AppColors.ink2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          // 從尖角那一點「彈」出來，像泡泡從卡片冒出來。
          child: ScaleTransition(
            alignment: Alignment(arrowX / width * 2 - 1, placeAbove ? 1 : -1),
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
              reverseCurve: Curves.easeIn,
            ),
            child: Material(
              color: Colors.transparent,
              child: CustomPaint(
                painter: _BubblePainter(arrowX: arrowX, arrowDown: placeAbove),
                child: Padding(
                  padding: const EdgeInsets.all(_padding),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in normal) cell(item),
                      if (hasDivider)
                        Container(
                          width: 1,
                          height: _itemHeight - 22,
                          margin: const EdgeInsets.symmetric(
                            horizontal: (_dividerWidth - 1) / 2,
                          ),
                          color: AppColors.glassEdge,
                        ),
                      for (final item in danger) cell(item),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 畫泡泡本體（圓角黑底＋細亮邊＋陰影）和指向卡片的小尖角。
class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.arrowX, required this.arrowDown});

  final double arrowX;
  final bool arrowDown;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final arrow = Path();
    if (arrowDown) {
      arrow
        ..moveTo(arrowX - _arrowHeight, size.height - 1)
        ..lineTo(arrowX, size.height + _arrowHeight)
        ..lineTo(arrowX + _arrowHeight, size.height - 1)
        ..close();
    } else {
      arrow
        ..moveTo(arrowX - _arrowHeight, 1)
        ..lineTo(arrowX, -_arrowHeight)
        ..lineTo(arrowX + _arrowHeight, 1)
        ..close();
    }
    final shape = Path()
      ..addRRect(body)
      ..addPath(arrow, Offset.zero);
    canvas.drawShadow(shape, Colors.black, 10, false);
    canvas.drawPath(shape, Paint()..color = _bubbleColor);
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.glassEdge,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.arrowX != arrowX || old.arrowDown != arrowDown;
}

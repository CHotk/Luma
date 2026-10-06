import 'dart:async';
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
    this.enabled = true,
  });

  final T value;
  final IconData icon;
  final String label;
  final Color? iconColor;
  final bool destructive;

  /// false＝照樣顯示、但反灰，點了或滑過去都沒反應（2026-10-06 使用者
  /// 要求：頻道已經在一般區時，「一般」不要藏起來，反灰就好，按鈕位置
  /// 才不會跳來跳去）。
  final bool enabled;
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
///
/// [drag] 有給的話，長按的手指不用放開，直接滑到某個按鈕上放開就選它
/// （2026-10-06 使用者要求）；在按鈕以外的地方放開，選單照樣留著可以
/// 再點。卡片用 [BubbleLongPress] 包起來就會自動接好。
Future<T?> showBubbleMenu<T>(
  BuildContext context, {
  required Rect anchor,
  required List<BubbleMenuItem<T>> items,
  BubbleMenuDrag? drag,
}) {
  final normal = items.where((e) => !e.destructive).toList();
  final danger = items.where((e) => e.destructive).toList();
  // 不用 showGeneralDialog 推一個新 route：推 route 時 Navigator 會把當下
  // 還按著的手指整個取消，長按的手指就收不到後面的移動、放開，沒辦法
  // 「滑過去選」（2026-10-06）。改成直接插在最上層 Overlay，返回鍵用
  // LocalHistoryEntry 接住，按返回一樣是關選單、不是離開這頁。
  final completer = Completer<T?>();
  final overlay = Overlay.of(context, rootOverlay: true);
  final route = ModalRoute.of(context);
  final hostKey = GlobalKey<_BubbleMenuHostState<T>>();
  late final OverlayEntry entry;
  LocalHistoryEntry? history;
  var closed = false;

  Future<void> finish(T? value) async {
    if (closed) return;
    closed = true;
    final h = history;
    history = null;
    if (h != null) route?.removeLocalHistoryEntry(h);
    completer.complete(value);
    await hostKey.currentState?.close();
    entry.remove();
  }

  if (route != null) {
    history = LocalHistoryEntry(
      onRemove: () {
        history = null;
        finish(null);
      },
    );
    route.addLocalHistoryEntry(history!);
  }
  entry = OverlayEntry(
    builder: (_) => _BubbleMenuHost<T>(
      key: hostKey,
      anchor: anchor,
      normal: normal,
      danger: danger,
      drag: drag,
      onSelect: finish,
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

/// 長按的手指在螢幕上的位置，從卡片的長按手勢一路轉給已經跳出來的
/// 泡泡選單。
class BubbleMenuDrag {
  BubbleMenuDrag({this.origin});

  /// 長按成立那一點，輔助虛線從這裡拉到手指目前的位置。
  final Offset? origin;
  final position = ValueNotifier<Offset?>(null);
  final released = ValueNotifier<bool>(false);

  void move(Offset global) => position.value = global;

  void release(Offset global) {
    position.value = global;
    released.value = true;
  }
}

/// 包住卡片：長按跳出泡泡選單，手指不放開可以直接滑到按鈕上放開來選
/// （見 [showBubbleMenu] 的 `drag`）。[onLongPress] 拿到卡片的範圍跟
/// 這次長按的 [BubbleMenuDrag]，自己呼叫 [showBubbleMenu] 時傳進去。
class BubbleLongPress extends StatefulWidget {
  const BubbleLongPress({
    super.key,
    required this.onLongPress,
    required this.child,
  });

  final void Function(Rect anchor, BubbleMenuDrag drag) onLongPress;
  final Widget child;

  @override
  State<BubbleLongPress> createState() => _BubbleLongPressState();
}

class _BubbleLongPressState extends State<BubbleLongPress> {
  BubbleMenuDrag? _drag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (d) {
        final drag = _drag = BubbleMenuDrag(origin: d.globalPosition);
        widget.onLongPress(bubbleAnchorOf(context), drag);
      },
      onLongPressMoveUpdate: (d) => _drag?.move(d.globalPosition),
      onLongPressEnd: (d) {
        _drag?.release(d.globalPosition);
        _drag = null;
      },
      child: widget.child,
    );
  }
}

/// 選單本體外面那層：半透明遮罩（點了關閉）＋淡入淡出動畫。
class _BubbleMenuHost<T> extends StatefulWidget {
  const _BubbleMenuHost({
    super.key,
    required this.anchor,
    required this.normal,
    required this.danger,
    required this.drag,
    required this.onSelect,
  });

  final Rect anchor;
  final List<BubbleMenuItem<T>> normal;
  final List<BubbleMenuItem<T>> danger;
  final BubbleMenuDrag? drag;
  final void Function(T? value) onSelect;

  @override
  State<_BubbleMenuHost<T>> createState() => _BubbleMenuHostState<T>();
}

class _BubbleMenuHostState<T> extends State<_BubbleMenuHost<T>>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();

  Future<void> close() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: '關閉選單',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelect(null),
                child: const ColoredBox(color: Colors.black26),
              ),
            ),
          ),
          Positioned.fill(
            child: _BubbleMenuLayout<T>(
              animation: _controller,
              anchor: widget.anchor,
              normal: widget.normal,
              danger: widget.danger,
              drag: widget.drag,
              onSelect: widget.onSelect,
            ),
          ),
        ],
      ),
    );
  }
}

/// 從卡片自己的 context 算出它在螢幕上的範圍，給 [showBubbleMenu] 的
/// `anchor` 用。
Rect bubbleAnchorOf(BuildContext cardContext) {
  final box = cardContext.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 每一格的寬度上限；項目多、螢幕窄放不下時整排等比縮窄（見 build）。
const double _maxItemWidth = 58;
const double _itemHeight = 56;
const double _padding = 5;
const double _dividerWidth = 9;
const double _arrowHeight = 7;
const double _gap = 6;
const double _screenMargin = 8;
const Color _bubbleColor = Color(0xF20E0E14);

class _BubbleMenuLayout<T> extends StatefulWidget {
  const _BubbleMenuLayout({
    required this.animation,
    required this.anchor,
    required this.normal,
    required this.danger,
    required this.onSelect,
    this.drag,
  });

  final Animation<double> animation;
  final Rect anchor;
  final List<BubbleMenuItem<T>> normal;
  final List<BubbleMenuItem<T>> danger;
  final BubbleMenuDrag? drag;
  final void Function(T? value) onSelect;

  @override
  State<_BubbleMenuLayout<T>> createState() => _BubbleMenuLayoutState<T>();
}

class _BubbleMenuLayoutState<T> extends State<_BubbleMenuLayout<T>> {
  /// 每個按鈕在螢幕上的範圍，build 時算好，滑選時拿來比對手指在哪顆上。
  final _cells = <(Rect, BubbleMenuItem<T>)>[];

  /// 手指目前滑到的那顆（亮起來）。
  BubbleMenuItem<T>? _hovered;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.drag?.position.addListener(_onMove);
    widget.drag?.released.addListener(_onRelease);
  }

  @override
  void dispose() {
    widget.drag?.position.removeListener(_onMove);
    widget.drag?.released.removeListener(_onRelease);
    super.dispose();
  }

  BubbleMenuItem<T>? _itemAt(Offset? p) {
    if (p == null) return null;
    for (final (rect, item) in _cells) {
      if (!item.enabled) continue;
      // 上下放寬一點，手指滑過去不用剛好壓在圖示上。
      if (rect.inflate(6).contains(p) ||
          (p.dx >= rect.left &&
              p.dx < rect.right &&
              (p.dy - rect.center.dy).abs() < rect.height / 2 + 14)) {
        return item;
      }
    }
    return null;
  }

  /// 這次長按途中有沒有「拖過」：離長按那一點超過一小段、或曾經指到過
  /// 任何一顆按鈕，就算拖過——之後就算滑回卡片附近才放手，也當作滑選沒選
  /// 到、選單收掉（2026-10-06 使用者回報：指過按鈕又移開放手，選單沒取消）。
  bool _everDragged = false;

  void _onMove() {
    final drag = widget.drag!;
    final p = drag.position.value;
    final hit = _itemAt(p);
    final origin = drag.origin;
    if (hit != null ||
        (origin != null && p != null && (p - origin).distance > 16)) {
      _everDragged = true;
    }
    if (hit == _hovered || !mounted) return;
    setState(() => _hovered = hit);
  }

  void _onRelease() {
    final hit = _itemAt(widget.drag!.position.value);
    if (!mounted || _done) return;
    final drag = widget.drag!;
    final origin = drag.origin;
    final end = drag.position.value;
    // 途中拖過（見 [_everDragged]）或放手的位置離長按點夠遠，都算「滑選」。
    final dragged =
        _everDragged ||
        (origin != null && end != null && (end - origin).distance > 16);
    if (hit != null) {
      _done = true;
      widget.onSelect(hit.value);
    } else if (dragged) {
      // 拖過去卻沒指到任何按鈕就放手：當作不選，選單收掉
      // （2026-10-06 使用者要求）。
      _done = true;
      widget.onSelect(null);
    } else if (_hovered != null) {
      setState(() => _hovered = null);
    }
    // 沒拖、長按完原地放開：選單留著，改用點的。
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.animation;
    final anchor = widget.anchor;
    final normal = widget.normal;
    final danger = widget.danger;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final hasDivider = normal.isNotEmpty && danger.isNotEmpty;
    final count = normal.length + danger.length;
    final chrome = (hasDivider ? _dividerWidth : 0) + _padding * 2;
    // 項目一多（例如頻道選單有六個動作）窄螢幕會塞不下，就把每格縮窄，
    // 整條泡泡一定留在螢幕裡。
    final itemWidth = math.min(
      _maxItemWidth,
      (screen.width - _screenMargin * 2 - chrome) / math.max(count, 1),
    );
    final width = count * itemWidth + chrome;
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

    _cells.clear();
    var x = left + _padding;
    for (final item in normal) {
      _cells.add((
        Rect.fromLTWH(x, top + _padding, itemWidth, _itemHeight),
        item,
      ));
      x += itemWidth;
    }
    if (hasDivider) x += _dividerWidth;
    for (final item in danger) {
      _cells.add((
        Rect.fromLTWH(x, top + _padding, itemWidth, _itemHeight),
        item,
      ));
      x += itemWidth;
    }

    Widget cell(BubbleMenuItem<T> item) {
      final hovered = identical(item, _hovered);
      final color = item.destructive
          ? AppColors.bad
          : (item.iconColor ?? AppColors.ink);
      return Opacity(
        opacity: item.enabled ? 1 : 0.32,
        child: SizedBox(
          width: itemWidth,
          height: _itemHeight,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            // 反灰的按鈕點了什麼都不做，但要接住這一下，不然會穿到背後
            // 的遮罩、被當成「點外面」把選單關掉。
            splashFactory: item.enabled ? null : NoSplash.splashFactory,
            highlightColor: item.enabled ? null : Colors.transparent,
            onTap: !item.enabled
                ? () {}
                : () {
                    if (_done) return;
                    _done = true;
                    widget.onSelect(item.value);
                  },
            // 滑選中的那顆：放大後彈一下（elasticOut，Q 彈）、底色換成強調色
            // （刪除這類用紅色）、字變亮（2026-10-06 使用者要求，參考 iOS
            // 長按選單／LINE 泡泡選單滑過去時的回饋）。
            child: AnimatedScale(
              scale: hovered ? 1.16 : 1,
              duration: Duration(milliseconds: hovered ? 420 : 140),
              curve: hovered ? Curves.elasticOut : Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: hovered
                      ? (item.destructive ? AppColors.bad : AppColors.accent)
                            .withValues(alpha: 0.28)
                      : Colors.transparent,
                ),
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
                        fontWeight: hovered ? FontWeight.w800 : FontWeight.w600,
                        color: item.destructive
                            ? AppColors.bad
                            : hovered
                            ? AppColors.ink
                            : AppColors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final drag = widget.drag;
    return Stack(
      children: [
        // 長按不放滑動時，從長按那一點拉一條虛線到手指（2026-10-06 使用者
        // 要求的輔助線），滑到按鈕上就變強調色；放開就收掉。
        if (drag != null && drag.origin != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GuideLinePainter(
                  drag: drag,
                  active: _hovered != null,
                  danger: _hovered?.destructive ?? false,
                ),
              ),
            ),
          ),
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

/// 滑選時的輔助虛線：起點一個小圓點（長按的位置），終點一個圈（手指
/// 目前的位置）。跟著手指移動重畫，不用整個選單重建。
class _GuideLinePainter extends CustomPainter {
  _GuideLinePainter({
    required this.drag,
    required this.active,
    required this.danger,
  }) : super(repaint: Listenable.merge([drag.position, drag.released]));

  final BubbleMenuDrag drag;
  final bool active;
  final bool danger;

  @override
  void paint(Canvas canvas, Size size) {
    final from = drag.origin;
    final to = drag.position.value;
    if (from == null || to == null || drag.released.value) return;
    final distance = (to - from).distance;
    if (distance < 12) return;

    final color = active
        ? (danger ? AppColors.bad : AppColors.accent)
        : AppColors.ink3;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 6.0;
    const gap = 5.0;
    final dir = (to - from) / distance;
    for (var d = 0.0; d < distance; d += dash + gap) {
      final end = math.min(d + dash, distance);
      canvas.drawLine(from + dir * d, from + dir * end, paint);
    }
    canvas.drawCircle(from, 3.5, Paint()..color = color);
    canvas.drawCircle(
      to,
      active ? 9 : 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GuideLinePainter old) =>
      old.active != active || old.danger != danger || old.drag != drag;
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

import 'dart:ui';

import 'package:flutter/material.dart';

/// 分頁列上的一格。
class FloatingTab {
  const FloatingTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// iOS 26 那種浮在下面的毛玻璃膠囊分頁列（2026-10-14 使用者選設計稿
/// 第 2 版，不要獨立搜尋鈕）。全 App 共用這一個元件，各功能只決定放哪幾格
/// （見 `app_bottom_nav.dart`）。
///
/// - 選中那格底下一塊亮玻璃，換分頁時彈一下滑過去。
/// - [collapsed]：往下滑時縮成一顆（只剩目前那格），點它就展開
///   （[onExpand]）；預設展開。
/// - [selected] 是 null 時沒有亮玻璃（例如在 App 首頁，三格都不是）。
class FloatingTabBar extends StatefulWidget {
  const FloatingTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
    this.onExpand,
    this.onLongPress,
  });

  final List<FloatingTab> tabs;
  final int? selected;
  final ValueChanged<int> onTap;
  final bool collapsed;
  final VoidCallback? onExpand;

  /// 長按某一格（例如 YT「影片」長按換頻道）。
  final ValueChanged<int>? onLongPress;

  /// 一格多寬、整條多高（外面算底部要讓多少空間用）。
  static const itemWidth = 84.0;
  static const height = 62.0;

  /// iOS 系統藍。
  static const tint = Color(0xFF0A84FF);

  @override
  State<FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<FloatingTabBar> {
  int? _pressed;

  static const _pad = 4.0;
  static const _spring = Cubic(0.3, 1.35, 0.4, 1);

  @override
  Widget build(BuildContext context) {
    final w = FloatingTabBar.itemWidth;
    final selected = widget.selected;
    // 縮起來只留目前那格（沒有選中的就不縮）。
    final collapsed = widget.collapsed && selected != null;
    final shown = collapsed
        ? [selected]
        : [for (var i = 0; i < widget.tabs.length; i++) i];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: _spring,
      width: shown.length * w + _pad * 2,
      height: FloatingTabBar.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FloatingTabBar.height / 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FloatingTabBar.height / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(FloatingTabBar.height / 2),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
            ),
            child: Stack(
              children: [
                // 選中那格底下的亮玻璃。
                if (selected != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 380),
                    curve: _spring,
                    left: _pad + (collapsed ? 0 : selected * w),
                    top: _pad,
                    bottom: _pad,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          FloatingTabBar.height / 2 - _pad,
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(_pad),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      maxWidth: double.infinity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [for (final i in shown) _item(i, collapsed)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i, bool collapsed) {
    final tab = widget.tabs[i];
    final on = i == widget.selected;
    final color = on ? FloatingTabBar.tint : Colors.white;
    return Semantics(
      button: true,
      selected: on,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = i),
        onTapCancel: () => setState(() => _pressed = null),
        onTapUp: (_) => setState(() => _pressed = null),
        onTap: () => collapsed ? widget.onExpand?.call() : widget.onTap(i),
        onLongPress: widget.onLongPress == null || collapsed
            ? null
            : () => widget.onLongPress!(i),
        child: AnimatedScale(
          scale: _pressed == i ? 0.88 : 1,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(
            width: FloatingTabBar.itemWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(on ? tab.selectedIcon : tab.icon, size: 24, color: color),
                const SizedBox(height: 1),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

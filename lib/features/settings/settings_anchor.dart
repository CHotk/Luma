import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../shared/widgets/glass_card.dart';

/// 設定頁搜尋用的「錨點」（2026-10-15）：每個設定項目包一層
/// [SettingAnchor]，搜尋結果點下去就能捲到那一項、閃一下。
class SettingsAnchors extends InheritedWidget {
  const SettingsAnchors({
    super.key,
    required this.keys,
    required this.highlight,
    required super.child,
  });

  /// 錨點 id → 那一項的 key（第一次畫到時建立）。
  final Map<String, GlobalKey> keys;

  /// 正在閃的那一項。
  final ValueListenable<String?> highlight;

  static SettingsAnchors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsAnchors>();

  @override
  bool updateShouldNotify(SettingsAnchors old) =>
      old.keys != keys || old.highlight != highlight;
}

/// 一個設定項目。外面沒有 [SettingsAnchors]（例如測試單獨畫一個區塊）
/// 就原樣顯示。
class SettingAnchor extends StatelessWidget {
  const SettingAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = SettingsAnchors.maybeOf(context);
    if (scope == null) return child;
    return KeyedSubtree(
      key: scope.keys.putIfAbsent(id, GlobalKey.new),
      child: ValueListenableBuilder<String?>(
        valueListenable: scope.highlight,
        builder: (context, lit, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (lit == id)
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

/// 設定頁一個功能一個區塊（2026-10-15 使用者要「最終版 2」：照設計稿
/// 第 1 版 iOS 設定那樣，一個功能一塊圓角底，裡面一列一列用細線隔開，
/// 每列左邊彩色小圖示）。[color] 是這個功能的顏色，裡面的 [SettingIcon]
/// 都用它。
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({super.key, required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 區塊裡不用卡片之間的空隙，改成細線。
    final rows = [
      for (final c in children)
        if (!(c is SizedBox && c.child == null)) c,
    ];
    return _BlockScope(
      color: color,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  indent: 52,
                  color: AppColors.glassEdge,
                ),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockScope extends InheritedWidget {
  const _BlockScope({required this.color, required super.child});

  final Color color;

  static _BlockScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BlockScope>();

  @override
  bool updateShouldNotify(_BlockScope old) => old.color != color;
}

/// 區塊裡的一列。在 [SettingsBlock] 外面（例如單獨畫）就跟原本一樣是一張
/// 玻璃卡片。
class SettingsRowCard extends StatelessWidget {
  const SettingsRowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (_BlockScope.maybeOf(context) == null) {
      return GlassCard(padding: padding, child: child);
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: padding.horizontal / 2,
        vertical: 11,
      ),
      child: child,
    );
  }
}

/// 列最左邊的彩色小方塊圖示（iOS 設定那種），顏色跟著所在的區塊。
class SettingIcon extends StatelessWidget {
  const SettingIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? _BlockScope.maybeOf(context)?.color ?? AppColors.ink3;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 17, color: Colors.white),
    );
  }
}

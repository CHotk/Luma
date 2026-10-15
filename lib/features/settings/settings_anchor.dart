import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

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

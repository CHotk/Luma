import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';

/// 「先顯示舊的、背景更新」用的兩個小元件（2026-10-02 使用者從五種風格
/// 裡選了第 5 版，見 `design-history/2026-10-02_空狀態與載入中五種風格.html`）：
/// 有快取就先把快取的內容秀出來，同時在上面放 [ThinRefreshBar]＋
/// [RefreshingPill] 告訴使用者「背景正在拿新的」，不讓畫面空著轉圈等。

/// 頂端一條 2px 的細進度條（不確定進度，來回跑）。
class ThinRefreshBar extends StatelessWidget {
  const ThinRefreshBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        minHeight: 2,
        color: AppColors.accent,
        backgroundColor: AppColors.accent.withValues(alpha: 0.12),
      ),
    );
  }
}

/// 小膠囊：轉圈＋一句話（例如「正在檢查新影片…」）。
class RefreshingPill extends StatelessWidget {
  const RefreshingPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: AppText.note),
          ],
        ),
      ),
    );
  }
}

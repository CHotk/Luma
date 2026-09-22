import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';

/// 考試相關三個頁面（模式選擇、選題範圍、作答）共用的頂部列：
/// 返回、標題、考試紀錄入口。三個頁面各自貼一份長得一樣的 Row 容易
/// 越改越不一致（之前作答頁的歷史按鈕就悄悄多長出幾個縮小樣式屬性，
/// 跟另外兩頁對不起來），抽成共用元件才能保證真的是同一顆按鈕、同一個
/// 位置（2026-09-21 使用者要求：點進考試以後頂部都固定，右上角始終
/// 能看歷史，只有標題文字不同）。
class KanaExamHeaderBar extends StatelessWidget {
  const KanaExamHeaderBar({super.key, required this.title, this.trailing});

  final String title;

  /// 只有作答頁需要在歷史按鈕後面多塞一個題號 chip，其他兩頁不用。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, size: 20),
          color: AppColors.ink2,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        const SizedBox(width: Gap.xs),
        Expanded(
          child: Text(
            title,
            style: AppText.title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          onPressed: () => context.push('/kana-exam/history'),
          icon: const Icon(Icons.history, size: 20),
          color: AppColors.ink2,
          tooltip: '考試紀錄',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        if (trailing != null) ...[const SizedBox(width: Gap.xs), trailing!],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';

/// 全 App 統一的確認對話框（刪除、清空、離開不儲存這類「確定要這樣做
/// 嗎？」）。2026-10-02 使用者從 `design-history/2026-10-02_確認對話框與
/// 提示五種風格.html` 挑了第 2 版「深色對話框＋上方毛玻璃提示」，但要
/// 文字居中，而且整個 App 統一——之前各頁各自組 [AlertDialog]，「刪除」
/// 鍵有的紅色實心、有的紅字、有的藍字，所以集中成這一個函式，不要在
/// 個別頁面再自己組確認框。
///
/// [destructive] 為 true（預設）時確認鍵是紅色實心（[AppColors.bad]），
/// 不可逆的動作都用這個；false 時是一般強調色。按取消、點外面或返回鍵
/// 都回傳 false。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.ink, fontSize: 16),
      ),
      content: message == null
          ? null
          : Text(message, textAlign: TextAlign.center, style: AppText.bodyDim),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.bad : AppColors.accent,
            foregroundColor: const Color(0xFF1A1A24),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

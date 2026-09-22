import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';

/// API 金鑰輸入/查看/清除的懸浮視窗。一進 YT 頻道追蹤頁（沒存過金鑰時）
/// 跟頂部列的鑰匙圖示都會開這個，同一顆元件，不要各刻一份
/// （2026-09-22 使用者要求：進來先跳懸浮視窗輸入，也要有地方看目前
/// 有沒有存、可以清除）。
///
/// 金鑰只放 [ytApiKeyProvider] 那個記憶體 provider，不寫進
/// localStorage——使用者明確要求關掉分頁／重新整理就要消失，不要長期
/// 留著，比較安全。
Future<void> showYtApiKeyDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(ytApiKeyProvider);
  final controller = TextEditingController(text: current ?? '');
  var obscure = true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text(
          'YouTube API 金鑰',
          style: TextStyle(color: AppColors.ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  current == null || current.isEmpty
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                  size: 16,
                  color: current == null || current.isEmpty
                      ? AppColors.ink3
                      : AppColors.ok,
                ),
                const SizedBox(width: Gap.xs),
                Text(
                  current == null || current.isEmpty ? '目前沒有儲存金鑰' : '目前有金鑰儲存中',
                  style: AppText.note,
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: controller,
              obscureText: obscure,
              autofocus: current == null || current.isEmpty,
              decoration: InputDecoration(
                hintText: '貼上 API 金鑰',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setDialogState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  color: AppColors.ink3,
                ),
              ),
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              '只存在這個分頁的記憶體裡，不會寫進瀏覽器儲存空間、也不會進\nGit——關掉分頁或重新整理就會消失，下次要重新貼一次。',
              style: AppText.note,
            ),
          ],
        ),
        actions: [
          if (current != null && current.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(ytApiKeyProvider.notifier).state = null;
                Navigator.pop(dialogContext);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.bad),
              child: const Text('清除金鑰'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              ref.read(ytApiKeyProvider.notifier).state =
                  value.isEmpty ? null : value;
              Navigator.pop(dialogContext);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ytAccent,
              foregroundColor: AppColors.ytAccentInk,
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
    ),
  );
}

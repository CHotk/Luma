import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';

/// 剪貼簿內容看起來像不像一把 API 金鑰的簡單判斷——不是真的去問
/// Google 這把金鑰存不存在，只是排除掉「顯然不是」的內容（網址、
/// 一句話、帶空白的文字……），單純長度＋字元集篩選，不追求精準
/// （2026-09-23 使用者要求：貼上前能判斷就先判斷）。Google API 金鑰
/// 目前都是 `AIza` 開頭的 39 字元，但限制型金鑰或之後改格式不一定
/// 符合，所以 `AIza` 開頭優先判定，符合不了才退回寬鬆的字元集規則。
bool _looksLikeApiKey(String text) {
  final trimmed = text.trim();
  if (trimmed.contains(RegExp(r'\s'))) return false;
  if (RegExp(r'^AIza[\w-]{35}$').hasMatch(trimmed)) return true;
  return trimmed.length >= 20 &&
      trimmed.length <= 64 &&
      RegExp(r'^[\w-]+$').hasMatch(trimmed);
}

/// API 金鑰輸入/查看/清除的懸浮視窗。一進 YT 頻道追蹤頁（沒存過金鑰時）
/// 跟頂部列的鑰匙圖示都會開這個，同一顆元件，不要各刻一份
/// （2026-09-22 使用者要求：進來先跳懸浮視窗輸入，也要有地方看目前
/// 有沒有存、可以清除）。
///
/// 打開時會先看一眼剪貼簿，像金鑰的內容就秀一顆「貼上並儲存」——跟
/// 百度網盤偵測到分享碼會主動問要不要貼上同一種體驗，一鍵貼上＋送出，
/// 不用自己長按貼上再點儲存兩個動作（2026-09-23 使用者要求）。
///
/// 金鑰只放 [ytApiKeyProvider] 那個記憶體 provider，不寫進
/// localStorage——使用者明確要求關掉分頁／重新整理就要消失，不要長期
/// 留著，比較安全。
Future<void> showYtApiKeyDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(ytApiKeyProvider);
  final controller = TextEditingController(text: current ?? '');
  var obscure = true;

  // 剪貼簿讀取是 async，要在開 dialog 之前先問完，dialog 的 builder
  // 本身不能是 async。讀不到（權限被擋、瀏覽器不支援）就當沒有候選，
  // 不影響原本手動貼上的流程。
  String? clipboardCandidate;
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && text != current && _looksLikeApiKey(text)) {
      clipboardCandidate = text;
    }
  } catch (_) {
    clipboardCandidate = null;
  }
  if (!context.mounted) return;

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
            if (clipboardCandidate != null) ...[
              const SizedBox(height: Gap.sm),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.ytAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.ytAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.content_paste_go_rounded,
                      size: 16,
                      color: AppColors.ytAccent,
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Text(
                        '偵測到剪貼簿有疑似金鑰的內容',
                        style: AppText.note,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(ytApiKeyProvider.notifier).state =
                            clipboardCandidate;
                        Navigator.pop(dialogContext);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.ytAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('貼上並儲存'),
                    ),
                  ],
                ),
              ),
            ],
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

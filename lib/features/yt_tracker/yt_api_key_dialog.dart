import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_api_key_store.dart';

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
Future<void> showYtApiKeyDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _YtApiKeyDialog(),
  );
}

class _YtApiKeyDialog extends ConsumerStatefulWidget {
  const _YtApiKeyDialog();

  @override
  ConsumerState<_YtApiKeyDialog> createState() => _YtApiKeyDialogState();
}

class _YtApiKeyDialogState extends ConsumerState<_YtApiKeyDialog> {
  late final TextEditingController _controller;
  var _obscure = true;
  String? _clipboardCandidate;

  @override
  void initState() {
    super.initState();
    final current = ref.read(ytApiKeyProvider);
    _controller = TextEditingController(text: current ?? '');
    // 打開時會先看一眼剪貼簿，像金鑰的內容就秀一顆「貼上並儲存」——跟
    // 百度網盤偵測到分享碼會主動問要不要貼上同一種體驗，一鍵貼上＋送出
    // （2026-09-23 使用者要求）。
    //
    // 一定要在 dialog 已經開著、widget 已經 mount 之後才讀剪貼簿，不能
    // 在 showDialog 之前就先讀——瀏覽器讀剪貼簿常常會跳權限詢問，使用者
    // 按「允許」那個當下，如果 dialog 都還沒開，等權限答覆回來時原本
    // 那次檢查早就結束、判斷完「沒有候選」了，dialog 開出來自然什麼都
    // 不會顯示，使用者只會覺得「要求了權限，結果什麼都沒發生」——還是
    // 得自己手動貼一次（2026-09-23 使用者實測回報的正是這個現象）。
    // 現在改成 initState 裡才發起讀取，讀完用 setState 更新，不管權限
    // 詢問花多久，畫面都還在、都能即時反映結果。
    _checkClipboard(current);
  }

  Future<void> _checkClipboard(String? current) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null &&
          text.isNotEmpty &&
          text != current &&
          _looksLikeApiKey(text) &&
          mounted) {
        setState(() => _clipboardCandidate = text);
      }
    } catch (_) {
      // 權限被擋、瀏覽器不支援：當沒有候選，不影響手動貼上的路。
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _persistAndClose(String? value) async {
    ref.read(ytApiKeyProvider.notifier).state = value;
    final store = YtApiKeyStore(ref.read(keyValueStoreProvider));
    if (value == null) {
      await store.clear();
    } else {
      await store.save(value);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(ytApiKeyProvider);
    final hasKey = current != null && current.isNotEmpty;

    return AlertDialog(
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
                hasKey ? Icons.lock_outline : Icons.lock_open_outlined,
                size: 16,
                color: hasKey ? AppColors.ok : AppColors.ink3,
              ),
              const SizedBox(width: Gap.xs),
              Text(hasKey ? '目前有金鑰儲存中' : '目前沒有儲存金鑰', style: AppText.note),
            ],
          ),
          if (_clipboardCandidate != null) ...[
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
                  const Expanded(
                    child: Text('偵測到剪貼簿有疑似金鑰的內容', style: AppText.note),
                  ),
                  TextButton(
                    onPressed: () => _persistAndClose(_clipboardCandidate),
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
            controller: _controller,
            obscureText: _obscure,
            autofocus: !hasKey,
            decoration: InputDecoration(
              hintText: '貼上 API 金鑰',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
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
            '會存在這台裝置的瀏覽器裡，但只留到明天 00:00——過了就自動\n清掉，不會無限期留著，也不會進 Git。',
            style: AppText.note,
          ),
        ],
      ),
      actions: [
        if (hasKey)
          TextButton(
            onPressed: () => _persistAndClose(null),
            style: TextButton.styleFrom(foregroundColor: AppColors.bad),
            child: const Text('清除金鑰'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            _persistAndClose(value.isEmpty ? null : value);
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ytAccent,
            foregroundColor: AppColors.ytAccentInk,
          ),
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

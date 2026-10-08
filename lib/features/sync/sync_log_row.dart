import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/sync_log_entry.dart';
import '../../shared/widgets/app_notice.dart';

/// 同步紀錄的一筆（同步頁的最近 10 筆、全部紀錄頁共用）。

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  return '${diff.inDays} 天前';
}

String _absoluteTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)}  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// detail 是「；」分功能、「、」分項目的一整串文字（見 r2_sync_section
/// 跟備份下載寫入的格式），畫面上拆成一項一行才不會全擠在同一行。
List<String> _detailLines(String detail) => detail
    .split(RegExp('[；、]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// 裝置名稱（「iOS・Safari」「Windows・Chrome」）前面配平台自己的圖示
/// （2026-10-08 使用者要求：iOS 用 Apple、Windows 用 Windows、Android 用
/// Android 的圖案）。Material 沒有 Windows 商標，用四格視窗 [Icons.window]，
/// 樣子跟 Windows 標誌一樣。
IconData deviceIcon(String? device) {
  final d = device ?? '';
  if (d.startsWith('iOS') || d.startsWith('Mac')) return Icons.apple;
  if (d.startsWith('Android')) return Icons.android;
  if (d.startsWith('Windows')) return Icons.window;
  if (d.startsWith('Linux')) return Icons.computer;
  return Icons.devices_other;
}

class SyncLogRow extends StatelessWidget {
  const SyncLogRow({super.key, required this.entry});

  final SyncLogEntry entry;

  /// 失敗紀錄右上角「複製」整筆的內容（2026-10-08 使用者要求：方便複製
  /// 錯誤訊息）。
  String get _copyText => [
    '${entry.action.label}${entry.success ? '' : '失敗'}',
    '${_absoluteTime(entry.at)}  ${entry.device ?? '未知裝置'}',
    if (entry.detail != null) entry.detail!,
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final color = entry.success ? AppColors.ok : AppColors.bad;
    final lines = entry.detail == null
        ? const <String>[]
        : _detailLines(entry.detail!);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.success ? Icons.check_circle : Icons.error_outline,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                '${entry.action.label}${entry.success ? '' : '失敗'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(_relativeTime(entry.at), style: AppText.note),
              if (!entry.success)
                IconButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _copyText));
                    if (context.mounted) {
                      showAppNotice(context, '已複製錯誤訊息');
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  color: AppColors.ink2,
                  tooltip: '複製錯誤訊息',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 28,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 21),
            child: Row(
              children: [
                Text(_absoluteTime(entry.at), style: AppText.note),
                const SizedBox(width: 8),
                Icon(deviceIcon(entry.device), size: 14, color: AppColors.ink2),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    entry.device ?? '未知裝置',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.note,
                  ),
                ),
              ],
            ),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: entry.success
                                ? AppColors.ink2
                                : AppColors.bad,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

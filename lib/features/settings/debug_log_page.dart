import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/notifications/test_notification_action.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_notice.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';

enum _Filter { all, error, info }

/// 「查看除錯訊息」：手機瀏覽器不方便叫出開發者工具看 console，這頁
/// 把 [AppLog] 存的最近幾百筆訊息列出來，可以整份複製貼給人看
/// （2026-09-18 使用者要求）。用 [ValueListenableBuilder] 接
/// [AppLog.entries]，頁面開著的時候新發生的錯誤會即時補進來，不用
/// 手動重整。
///
/// 版面是設計稿 07（分級篩選）＋08（卡片摘要）＋10（頂部總覽）三版
/// 合起來（2026-09-23 使用者決定）。篩選只有「全部／錯誤／一般」兩級，
/// 不是 07 原稿畫的三級（多一個「警告」）——[AppLogEntry] 目前只有
/// `isError` 一個布林欄位，沒有真的警告等級資料，不無中生有做一個假的
/// 篩選項出來。
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

const _testMessages = [
  '[YtApi] fetchChannelInfo(@shasha77) 開始',
  '[YtApi] fetchDurations 失敗：quotaExceeded',
  '[Diary] loadEntries() 共 42 筆',
  '[ExternalLink] window.open 失敗：popup blocked',
  '[KanaExam] submit answer id=88 正確',
  '[Fitness] mergeSeed 完成，共 3 筆',
  '[Notif] requestPermission() → granted',
];

class _DebugLogPageState extends State<DebugLogPage> {
  _Filter _filter = _Filter.all;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    AppLog.markViewed();
  }

  /// 隨便產生一筆訊息，嚴重等級（一般／錯誤）也隨機決定——這樣才有
  /// 兩種等級的訊息可以測，不用真的等程式出包才能看除錯頁的篩選／
  /// 卡片顯示長怎樣（2026-09-23 使用者要求）。純測試用，訊息內容跟
  /// 真的錯不錯無關。
  void _addTestMessage() {
    final message = _testMessages[_random.nextInt(_testMessages.length)];
    AppLog.add(message, isError: _random.nextBool());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(
                  title: '除錯訊息',
                  showBack: false,
                  actions: [
                    IconButton(
                      onPressed: _addTestMessage,
                      icon: const Icon(Icons.bug_report_outlined, size: 20),
                      color: AppColors.ink2,
                      tooltip: '新增測試訊息',
                    ),
                    IconButton(
                      onPressed: () => testNotification(context),
                      icon: const Icon(
                        Icons.notifications_active_outlined,
                        size: 20,
                      ),
                      color: AppColors.ink2,
                      tooltip: '測試通知',
                    ),
                    ValueListenableBuilder<List<AppLogEntry>>(
                      valueListenable: AppLog.entries,
                      builder: (context, entries, _) => IconButton(
                        onPressed: entries.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(
                                  ClipboardData(text: _joined(entries)),
                                );
                                showAppNotice(context, '已複製到剪貼簿');
                              },
                        icon: const Icon(Icons.copy_all_outlined, size: 20),
                        color: AppColors.ink2,
                        tooltip: '複製全部',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: ValueListenableBuilder<List<AppLogEntry>>(
                    valueListenable: AppLog.entries,
                    builder: (context, entries, _) {
                      if (entries.isEmpty) {
                        return Center(
                          child: Text('還沒有任何訊息', style: AppText.bodyDim),
                        );
                      }
                      final errorCount = entries.where((e) => e.isError).length;
                      final lastError = entries
                          .where((e) => e.isError)
                          .fold<AppLogEntry?>(
                            null,
                            (latest, e) =>
                                latest == null || e.at.isAfter(latest.at)
                                ? e
                                : latest,
                          );
                      final filtered = switch (_filter) {
                        _Filter.all => entries,
                        _Filter.error =>
                          entries.where((e) => e.isError).toList(),
                        _Filter.info =>
                          entries.where((e) => !e.isError).toList(),
                      };
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StatRow(
                            total: entries.length,
                            errorCount: errorCount,
                            lastError: lastError,
                          ),
                          const SizedBox(height: Gap.sm),
                          _FilterRow(
                            selected: _filter,
                            total: entries.length,
                            errorCount: errorCount,
                            infoCount: entries.length - errorCount,
                            onSelect: (f) => setState(() => _filter = f),
                          ),
                          const SizedBox(height: Gap.sm),
                          Expanded(
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      '這個篩選條件下沒有訊息',
                                      style: AppText.bodyDim,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 6),
                                    itemBuilder: (context, i) =>
                                        _LogCard(entry: filtered[i]),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: Gap.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _joined(List<AppLogEntry> entries) =>
      entries.map(_LogCard.formatLine).join('\n');
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime d) => '${d.year}/${_two(d.month)}/${_two(d.day)}';

String _stamp(DateTime d) =>
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.'
    '${d.millisecond.toString().padLeft(3, '0')}';

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  return '${diff.inDays} 天前';
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.total,
    required this.errorCount,
    required this.lastError,
  });

  final int total;
  final int errorCount;
  final AppLogEntry? lastError;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(value: '$total', label: '總筆數'),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: _StatCard(
            value: '$errorCount',
            label: '錯誤總數',
            valueColor: errorCount > 0 ? AppColors.bad : null,
          ),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: _StatCard(
            value: lastError == null ? '無' : _relativeTime(lastError!.at),
            label: '最近一次錯誤',
            small: true,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    this.valueColor,
    this.small = false,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        children: [
          Text(
            value,
            style: small
                ? TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? AppColors.ink,
                  )
                : AppText.number.copyWith(fontSize: 18, color: valueColor),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.note, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selected,
    required this.total,
    required this.errorCount,
    required this.infoCount,
    required this.onSelect,
  });

  final _Filter selected;
  final int total;
  final int errorCount;
  final int infoCount;
  final ValueChanged<_Filter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: '全部',
          count: total,
          color: AppColors.accent,
          selected: selected == _Filter.all,
          onTap: () => onSelect(_Filter.all),
        ),
        const SizedBox(width: 6),
        _Chip(
          label: '錯誤',
          count: errorCount,
          color: AppColors.bad,
          selected: selected == _Filter.error,
          onTap: () => onSelect(_Filter.error),
        ),
        const SizedBox(width: 6),
        _Chip(
          label: '一般',
          count: infoCount,
          color: AppColors.accent,
          selected: selected == _Filter.info,
          onTap: () => onSelect(_Filter.info),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? color.withValues(alpha: 0.2) : AppColors.glassFill,
          border: Border.all(color: selected ? color : AppColors.glassEdge),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final AppLogEntry entry;

  static String formatLine(AppLogEntry e) =>
      '${_date(e.at)} ${_stamp(e.at)}  [${e.device ?? '未知裝置'}]  ${e.message}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: entry.isError
            ? AppColors.bad.withValues(alpha: 0.08)
            : AppColors.glassFill,
        border: Border.all(
          color: entry.isError
              ? AppColors.bad.withValues(alpha: 0.4)
              : AppColors.glassEdge,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.isError
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 13,
                color: entry.isError ? AppColors.bad : AppColors.ink3,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${_date(entry.at)} ${_stamp(entry.at)}  ·  ${entry.device ?? '未知裝置'}',
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 10,
                    color: AppColors.ink3,
                  ),
                ),
              ),
              // 每則訊息都能單獨複製（2026-09-24 使用者要求），貼給人看
              // 錯誤內容時不用整份複製再自己挑。
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: formatLine(entry)));
                  showAppNotice(context, '已複製這則訊息');
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: AppColors.ink3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.message,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 11.5,
              color: entry.isError ? AppColors.ink : AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

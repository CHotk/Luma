import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';

/// 「查看除錯訊息」：手機瀏覽器不方便叫出開發者工具看 console，這頁
/// 把 [AppLog] 存的最近幾百筆訊息列出來，可以整份複製貼給人看
/// （2026-09-18 使用者要求）。用 [ValueListenableBuilder] 接
/// [AppLog.entries]，頁面開著的時候新發生的錯誤會即時補進來，不用
/// 手動重整。
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 只在「本來就在底部附近」時才跟著新訊息捲到底——使用者往上滑在看
  /// 舊訊息時，不該被新進來的訊息硬拉走。
  void _followIfNearBottom(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    if (!atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
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
                  actions: [
                    ValueListenableBuilder<List<AppLogEntry>>(
                      valueListenable: AppLog.entries,
                      builder: (context, entries, _) => IconButton(
                        onPressed: entries.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(
                                  ClipboardData(text: _joined(entries)),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已複製到剪貼簿')),
                                );
                              },
                        icon: const Icon(Icons.copy_all_outlined, size: 20),
                        color: AppColors.ink2,
                        tooltip: '複製全部',
                      ),
                    ),
                    IconButton(
                      onPressed: () => AppLog.clear(),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      color: AppColors.ink2,
                      tooltip: '清空',
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
                      _followIfNearBottom(entries.length);
                      return ListView.builder(
                        controller: _scroll,
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _LogRow(entry: entries[i]),
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
      entries.map(_LogRow.formatLine).join('\n');
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final AppLogEntry entry;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime d) =>
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.'
      '${d.millisecond.toString().padLeft(3, '0')}';

  static String formatLine(AppLogEntry e) => '${_stamp(e.at)}  ${e.message}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${_stamp(entry.at)}  ',
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: AppColors.ink3,
              ),
            ),
            TextSpan(
              text: entry.message,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11.5,
                color: entry.isError ? AppColors.bad : AppColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

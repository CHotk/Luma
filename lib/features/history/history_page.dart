import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/history.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';

/// 總歷史。從第一天用到現在的累計，加上每一輪的明細。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyOverviewProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const Text('總紀錄', style: AppText.title),
                    const Spacer(),
                    // 手機跟電腦各自練的紀錄存在各自裝置裡，不會自動合併，
                    // 這顆按鈕把紀錄匯出成文字，讓使用者自己拿去手動合併。
                    IconButton(
                      onPressed: () => _showExportDialog(context, ref),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.ink2,
                      tooltip: '匯出紀錄',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到紀錄：$e', style: AppText.bodyDim)),
                    data: (data) => _Body(
                      stats: data.stats,
                      rounds: data.rounds,
                      activity: data.recent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 跳出匯出對話框，內容是跟 `history.txt` 同格式的文字，
/// 可以複製出去，之後貼給人工整理、合併回題庫的紀錄檔裡。
Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final text = await ref.read(historyRepositoryProvider).exportText();
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text('匯出紀錄', style: TextStyle(color: AppColors.ink)),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.ink2,
              fontFamily: 'Consolas',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('關閉'),
        ),
        FilledButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('已複製到剪貼簿')),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentSolid,
          ),
          child: const Text('複製'),
        ),
      ],
    ),
  );
}

/// 這頁要的三份資料一起抓，省掉畫面裡串好幾個 future。
final historyOverviewProvider =
    FutureProvider.autoDispose<
      ({LifetimeStats stats, List<RoundLog> rounds, List<HistoryEntry> recent})
    >((ref) async {
      ref.watch(dataRevisionProvider);
      final repo = ref.watch(historyRepositoryProvider);
      final entries = await repo.entries();
      return (
        stats: await repo.lifetime(),
        rounds: await repo.rounds(),
        // 最近十筆活動，新的排前面。
        recent: entries.reversed.take(10).toList(),
      );
    });

class _Body extends StatelessWidget {
  const _Body({
    required this.stats,
    required this.rounds,
    required this.activity,
  });

  final LifetimeStats stats;
  final List<RoundLog> rounds;

  /// 最近十筆單題紀錄，像交易明細那樣一條一條列。
  final List<HistoryEntry> activity;

  @override
  Widget build(BuildContext context) {
    if (stats.rounds == 0) {
      return const Center(
        child: Text('還沒有紀錄，做完一輪就會出現', style: AppText.bodyDim),
      );
    }

    // 新的排前面，看紀錄通常是想看最近做了什麼。
    final recent = rounds.reversed.toList();

    return ListView(
      children: [
        Row(
          children: [
            Expanded(child: _Tile('${stats.rounds}', '總輪數')),
            const SizedBox(width: Gap.sm),
            Expanded(child: _Tile('${stats.questions}', '總題數')),
            const SizedBox(width: Gap.sm),
            Expanded(child: _Tile('${stats.activeDays}', '使用天數')),
          ],
        ),
        const SizedBox(height: Gap.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelLabel('累計'),
              const SizedBox(height: Gap.sm),
              _Row('答對', '${stats.right} 題'),
              _Row('答錯', '${stats.wrong} 題'),
              _Row('正確率', '${(stats.accuracy * 100).toStringAsFixed(0)}%'),
              _Row('總作答時間', _duration(stats.seconds)),
              _Row('偽裝模式', '${stats.stealthRounds} 輪'),
              if (stats.since != null) _Row('從', _day(stats.since!)),
            ],
          ),
        ),
        if (activity.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          const PanelLabel('最近活動'),
          const SizedBox(height: Gap.xs),
          for (final e in activity) _ActivityRow(entry: e),
        ],

        const SizedBox(height: Gap.lg),
        const PanelLabel('每一輪'),
        const SizedBox(height: Gap.xs),
        for (final r in recent) _RoundRow(log: r),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  static String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h 小時 $m 分';
    return '$m 分 ${seconds % 60} 秒';
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _Tile extends StatelessWidget {
  const _Tile(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.number),
          const SizedBox(height: 1),
          Text(label, style: AppText.note),
        ],
      ),
    );
  }
}

/// 最近活動的一行。像交易明細：什麼字、答對還答錯、什麼時候。
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ok = entry.correct;
    // 舊資料只有日期沒有時分，那就只顯示日期，不要假裝有時間。
    final hasClock = entry.at.hour != 0 || entry.at.minute != 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.glassEdge)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: ok ? AppColors.ok : AppColors.statusPending,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              entry.word,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            ok ? '答對' : '答錯',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ok ? AppColors.ok : AppColors.statusPending,
            ),
          ),
          const SizedBox(width: Gap.md),
          SizedBox(
            width: 96,
            child: Text(
              hasClock ? _stamp(entry.at) : _dayOnly(entry.at),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.ink3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dayOnly(DateTime d) => '${_two(d.month)}-${_two(d.day)}';

  static String _stamp(DateTime d) =>
      '${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

class _RoundRow extends StatelessWidget {
  const _RoundRow({required this.log});

  final RoundLog log;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // 點進去看這一輪出了什麼題、你怎麼答的。
      onTap: () => context.push('/round/${log.round}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.glassEdge)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text('R${log.round}', style: AppText.bodyDim),
            ),
            Expanded(child: Text(_Body._day(log.at), style: AppText.note)),
            // 偽裝模式做的那幾輪標一下，自己看得懂就好。
            if (log.stealth)
              const Padding(
                padding: EdgeInsets.only(right: Gap.sm),
                child: Text(
                  'cmd',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.ink3,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
            Text(
              '${log.right} / ${log.total}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: log.right * 2 >= log.total
                    ? AppColors.ok
                    : AppColors.mid,
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.bodyDim),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/export/file_download.dart';
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

/// 跳出匯出對話框，內容是跟 `history.txt` 同格式的文字。
///
/// 主要動作是下載成檔案，網頁版跟手機瀏覽器打開同一個網頁版都是走瀏覽器
/// 原生下載（見 `data/export/file_download.dart`），不用另外裝 App。
/// 複製到剪貼簿留著當備用，下載萬一在某些瀏覽器環境不支援還有得用。
Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
  final text = await ref.read(historyRepositoryProvider).exportText();
  if (!context.mounted) return;

  final sizeLabel = _formatSize(utf8.encode(text).length);
  final filename = 'lume-history-${_todayStamp()}.txt';

  // 內容只是給使用者確認「有抓到東西」，不是拿來預覽全部，
  // 完整內容太長（成千上百行）沒必要整份塞進對話框，抓前三行示意就好。
  final lines = text.split('\n');
  final preview = lines.length > 3
      ? '${lines.take(3).join('\n')}\n...'
      : text;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '匯出紀錄',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$filename ・ 約 $sizeLabel',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.ink3),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            preview,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.ink2,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () {
            final ok = saveTextFile(filename, text);
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(
                content: Text(ok ? '已下載 $filename' : '這個平台還不支援下載，改用複製'),
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentSolid,
          ),
          child: const Text('下載'),
        ),
        OutlinedButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('已複製到剪貼簿')),
            );
          },
          child: const Text('複製'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('關閉'),
        ),
      ],
    ),
  );
}

/// 位元組數換算成好讀的大小，跟檔案總管一樣只到 KB／MB 這種常見單位。
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _todayStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
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
    // rounds 本身已經照真實時間排好（見 history_repository.dart），
    // 這裡按時間先後編出「第幾輪」給使用者看——一輪已經沒有編號了
    // （2026-09-17 決定拿掉），只能用 at（那一輪共用的識別時戳）當鍵。
    final sequence = {
      for (var i = 0; i < rounds.length; i++) rounds[i].at: i + 1,
    };
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
        for (final r in recent) _RoundRow(log: r, sequence: sequence[r.at]!),
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
  const _RoundRow({required this.log, required this.sequence});

  final RoundLog log;

  /// 按時間先後算出來的「第幾輪」，給使用者看的號碼——一輪已經沒有
  /// 編號了，路由用的是 [log.at]（見 history_page.dart 頂部
  /// `sequence` 的建構說明）。
  final int sequence;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // 點進去看這一輪出了什麼題、你怎麼答的。路由參數是 log.at
      // 編碼過的字串（唯一識別碼），畫面上顯示的號碼是另外算的 sequence。
      onTap: () =>
          context.push('/round/${Uri.encodeComponent(log.at.toIso8601String())}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.glassEdge)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text('R$sequence', style: AppText.bodyDim),
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

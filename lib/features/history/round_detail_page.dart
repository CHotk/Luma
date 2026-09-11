import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/history.dart';

/// 一輪的完整明細：出了哪些題、你怎麼答的。
///
/// 做這頁的理由是使用者想以後慢慢翻自己的進步，
/// 所以「當初打錯成什麼」比「答錯了」更有價值，要看得到。
class RoundDetailPage extends ConsumerWidget {
  const RoundDetailPage({super.key, required this.round});

  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(roundDetailProvider(round));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 20),
                    color: AppColors.ink2,
                  ),
                  Text('第 $round 輪', style: AppText.title),
                ],
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (e, _) =>
                      Center(child: Text('讀不到這輪：$e', style: AppText.bodyDim)),
                  data: (data) => _Body(data: data),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 這一輪的題目，外加每個字的中文。
/// 中文不存在紀錄裡，要去單字庫查，這樣才不會有兩份會不一致的中文。
final roundDetailProvider = FutureProvider.autoDispose
    .family<({List<HistoryEntry> entries, Map<String, String> zh}), int>((
      ref,
      round,
    ) async {
      final entries = await ref
          .watch(historyRepositoryProvider)
          .forRound(round);
      final words = await ref.watch(wordRepositoryProvider).loadAll();
      return (
        entries: entries,
        zh: {for (final w in words) w.word.toLowerCase(): w.zh},
      );
    });

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final ({List<HistoryEntry> entries, Map<String, String> zh}) data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries;
    if (entries.isEmpty) {
      return const Center(child: Text('這輪沒有紀錄', style: AppText.bodyDim));
    }

    final right = entries.where((e) => e.correct).length;

    return ListView(
      children: [
        Text(
          '$right / ${entries.length} 題答對　${_day(entries.first.at)}',
          style: AppText.bodyDim,
        ),
        const SizedBox(height: Gap.md),
        for (var i = 0; i < entries.length; i++)
          _EntryRow(
            index: i + 1,
            entry: entries[i],
            zh: data.zh[entries[i].word.toLowerCase()] ?? '',
          ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.index, required this.entry, required this.zh});

  final int index;
  final HistoryEntry entry;
  final String zh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.glassEdge)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 26, child: Text('$index', style: AppText.note)),
          SizedBox(
            width: 24,
            child: Text(
              entry.correct ? 'O' : 'X',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: entry.correct ? AppColors.ok : AppColors.bad,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.word,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (zh.isNotEmpty) ...[
                      const SizedBox(width: Gap.sm),
                      Flexible(
                        child: Text(
                          zh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.note,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(_detail(entry), style: AppText.note),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一行講清楚這題是什麼題型、你打了什麼、想了多久。
  static String _detail(HistoryEntry e) {
    final parts = <String>[
      e.typed ? '打字題' : '點選題',
      if (e.isReview) '回考',
      if (e.typed && e.input.isNotEmpty) '你打了 ${e.input}',
      if (e.typed && e.input.isEmpty) '沒有作答',
      if (e.seconds > 0) '想了 ${e.seconds} 秒',
    ];
    return parts.join('　');
  }
}

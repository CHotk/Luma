import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_exam.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import 'jp_home_controller.dart';

/// 日文軌道的學習統計總覽：練習跟考試兩邊的數字彙總在一頁，對應英文
/// 軌道首頁右上角的「總紀錄」（`/history`）——日文原本練習紀錄跟考試
/// 紀錄是兩個分開的頁面，各自只看得到自己那邊，沒有一個地方能一眼
/// 看完整體學習狀況（2026-09-21 使用者要求：英文右上角有統計，日文
/// 也應該要有）。
class JpStatsPage extends ConsumerWidget {
  const JpStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(jpHomeStateProvider);
    final examEntriesAsync = ref.watch(_examEntriesProvider);

    return Scaffold(
      body: AmbientBackground(
        background: AppColors.jpBg,
        blobColors: const [
          AppColors.jpAmb1,
          AppColors.jpAmb2,
          AppColors.jpAmb3,
          AppColors.jpAmb4,
        ],
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
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const SizedBox(width: Gap.xs),
                    const Text('📊 學習統計', style: AppText.title),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        homeAsync.when(
                          loading: () => const _LoadingCard(),
                          error: (e, _) => _ErrorCard(message: '$e'),
                          data: (state) => _PracticeSection(state: state),
                        ),
                        const SizedBox(height: Gap.md),
                        examEntriesAsync.when(
                          loading: () => const _LoadingCard(),
                          error: (e, _) => _ErrorCard(message: '$e'),
                          data: (entries) => _ExamSection(entries: entries),
                        ),
                        const SizedBox(height: Gap.lg),
                      ],
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

/// autoDispose：離開這頁就丟掉，回來時重新算，跟 [jpHomeStateProvider]
/// 同一套邏輯（見那邊的說明）。
final _examEntriesProvider = FutureProvider.autoDispose<List<KanaExamEntry>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(kanaExamRepositoryProvider).loadAll();
});

class _PracticeSection extends StatelessWidget {
  const _PracticeSection({required this.state});

  final JpHomeState state;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelLabel('手寫練習'),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              _StatTile(label: '今天練習', value: '${state.todayCount} 字'),
              _StatTile(label: '今天花費', value: '${state.todayMinutes} 分'),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              _StatTile(
                label: '已掌握',
                value: '${state.review.mastered}',
                color: AppColors.ok,
              ),
              _StatTile(
                label: '待複習',
                value: '${state.review.due}',
                color: AppColors.statusPending,
              ),
              _StatTile(
                label: '新字',
                value: '${state.review.fresh}',
                color: AppColors.statusUntested,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExamSection extends StatelessWidget {
  const _ExamSection({required this.entries});

  final List<KanaExamEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PanelLabel('手寫考試'),
            const SizedBox(height: Gap.sm),
            Text('還沒考過，去五十音考試練練看', style: AppText.bodyDim),
          ],
        ),
      );
    }

    final roundCount = entries.map((e) => e.roundId).toSet().length;
    final kanaEntries = entries.where((e) => e.examType == 'kana').toList();
    final vocabEntries = entries.where((e) => e.examType == 'vocab').toList();

    int accuracyOf(List<KanaExamEntry> list) {
      if (list.isEmpty) return 0;
      final correct = list.where((e) => e.isCorrect).length;
      return (correct / list.length * 100).round();
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelLabel('手寫考試'),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              _StatTile(label: '考試輪次', value: '$roundCount'),
              _StatTile(label: '總題數', value: '${entries.length}'),
              _StatTile(
                label: '整體正確率',
                value: '${accuracyOf(entries)}%',
                color: AppColors.jpAccent,
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              _StatTile(
                label: '50 音正確率',
                value: kanaEntries.isEmpty
                    ? '—'
                    : '${accuracyOf(kanaEntries)}%',
              ),
              _StatTile(
                label: '詞彙正確率',
                value: vocabEntries.isEmpty
                    ? '—'
                    : '${accuracyOf(vocabEntries)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.note, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Gap.lg),
          child: CircularProgressIndicator.adaptive(),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(child: Text('讀不到資料：$message', style: AppText.bodyDim));
  }
}

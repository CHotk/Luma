import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/kana_exam.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
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
      drawer: const AppSideDrawer(),
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
                const AppTopBar(title: '📊 學習統計'),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        homeAsync.when(
                          loading: () => const _LoadingCard(),
                          error: (e, _) => _ErrorCard(message: '$e'),
                          data: (state) => _SummarySection(state: state),
                        ),
                        const SizedBox(height: Gap.md),
                        // 手寫練習、手寫考試合併成一張「練習狀況」，卡片裡
                        // 再分練習／考試兩段（2026-10-05 使用者要求）。
                        switch ((homeAsync, examEntriesAsync)) {
                          (
                            AsyncData(value: final state),
                            AsyncData(value: final entries),
                          ) =>
                            _ProgressSection(state: state, exams: entries),
                          (AsyncError(:final error), _) ||
                          (
                            _,
                            AsyncError(:final error),
                          ) => _ErrorCard(message: '$error'),
                          _ => const _LoadingCard(),
                        },
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

/// 學習摘要：手寫練習＋考試加起來總共練過幾題，加上開始學習的日期、
/// 已經幾天（從第一天直接算到今天，沒練的日子也算）、有練的天數（只算
/// 真的有練習或考試的日子，2026-10-05 使用者要求兩種都要）、連續幾天（2026-10-05 使用者要求：原本「總共練過」跟「學習
/// 天數」兩張卡合併成一張；天數是整個日文學習的，練習、考試都算）。
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.state});

  final JpHomeState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalPracticeCount + state.totalExamCount;
    final start = state.firstPracticedAt;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelLabel('學習摘要'),
          const SizedBox(height: Gap.sm),
          Center(
            child: Text(
              '總共練過 $total 題',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.jpAccent,
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              _StatTile(label: '手寫練習', value: '${state.totalPracticeCount}'),
              _StatTile(label: '考試', value: '${state.totalExamCount}'),
              _StatTile(label: '今天', value: '${state.todayCount}'),
            ],
          ),
          if (start != null) ...[
            const SizedBox(height: Gap.sm),
            const Divider(height: 1, color: AppColors.glassEdge),
            const SizedBox(height: Gap.sm),
            Center(
              child: Text(
                '${start.year}/${start.month}/${start.day} 開始學習',
                style: AppText.note,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                _StatTile(label: '已經', value: '${state.daysSinceStart} 天'),
                _StatTile(
                  label: '有練的天數',
                  value: '${state.allPracticedDates.length} 天',
                ),
                _StatTile(label: '連續中', value: '${state.streakDays} 天'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 練習狀況：原本分開的「手寫練習」「手寫考試」兩張卡合併成一張，卡片裡
/// 用小標題分「練習」「考試」兩段（2026-10-05 使用者要求）。
class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.state, required this.exams});

  final JpHomeState state;
  final List<KanaExamEntry> exams;

  @override
  Widget build(BuildContext context) {
    final roundCount = exams.map((e) => e.roundId).toSet().length;
    final kanaExams = exams.where((e) => e.examType == 'kana').toList();
    final vocabExams = exams.where((e) => e.examType == 'vocab').toList();

    String accuracyOf(List<KanaExamEntry> list) {
      if (list.isEmpty) return '—';
      final correct = list.where((e) => e.isCorrect).length;
      return '${(correct / list.length * 100).round()}%';
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelLabel('練習狀況'),
          const SizedBox(height: Gap.sm),
          const _SubLabel('練習'),
          Row(
            children: [
              _StatTile(label: '總共練習', value: '${state.totalPracticeCount} 字'),
              _StatTile(label: '今天練習', value: '${state.todayPracticeCount} 字'),
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
          const SizedBox(height: Gap.md),
          const Divider(height: 1, color: AppColors.glassEdge),
          const SizedBox(height: Gap.sm),
          const _SubLabel('考試'),
          if (exams.isEmpty)
            Text('還沒考過，去五十音考試練練看', style: AppText.bodyDim)
          else ...[
            Row(
              children: [
                _StatTile(label: '考試輪次', value: '$roundCount'),
                _StatTile(label: '總題數', value: '${exams.length}'),
                _StatTile(
                  label: '整體正確率',
                  value: accuracyOf(exams),
                  color: AppColors.jpAccent,
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                _StatTile(label: '50 音正確率', value: accuracyOf(kanaExams)),
                _StatTile(label: '詞彙正確率', value: accuracyOf(vocabExams)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 卡片裡分段用的小標題。
class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.jpAccent,
        ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/quiz.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../home/home_controller.dart';
import '../quiz/quiz_controller.dart';

/// 結果頁。
///
/// 一條不能妥協的規則：答錯和沒答出來的字要全部列出來並附中文，
/// 一個都不能漏，也不要附記憶點。使用者要的是答案清單，不是講解。
class ResultPage extends ConsumerWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(lastRoundProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: result == null ? const _Empty() : _Body(result: result),
          ),
        ),
      ),
    );
  }
}

/// 沒有成績可看的時候。
///
/// 會走到這裡通常是中途離開，那時候 lastRound 還是空的。
/// 這頁一定要留一顆回首頁，不然就變成走不出去的死路。
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('這輪沒有成績', style: AppText.bodyDim),
        const SizedBox(height: Gap.xs),
        const Text('答過的題目已經記下來了', style: AppText.note),
        const SizedBox(height: Gap.lg),
        FilledButton(
          onPressed: () => context.go('/home'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.glassFill,
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.button),
            ),
          ),
          child: const Text('回首頁'),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.result});

  final RoundResult result;

  @override
  Widget build(BuildContext context) {
    final missed = result.missed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Gap.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${result.rightCount}',
              style: const TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.4,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Text('題答對 · 共 ${result.total} 題', style: AppText.bodyDim),
          ],
        ),

        const SizedBox(height: Gap.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelLabel('這輪'),
              const SizedBox(height: Gap.sm),
              _Row(
                '新字',
                '${result.countOf(review: false, correctOnly: true)}'
                    ' / ${result.countOf(review: false, correctOnly: false)}',
              ),
              _Row(
                '回考舊字',
                '${result.countOf(review: true, correctOnly: true)}'
                    ' / ${result.countOf(review: true, correctOnly: false)}',
              ),
              _Row('花了', _mmss(result.elapsed)),
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),
        const PanelLabel('答錯與沒答出來'),
        const SizedBox(height: Gap.xs),
        Expanded(
          child: missed.isEmpty
              ? const Center(child: Text('這輪全對', style: AppText.bodyDim))
              : ListView.separated(
                  itemCount: missed.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.glassEdge),
                  itemBuilder: (context, i) {
                    final w = missed[i].question.word;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            w.word,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(w.zh, style: AppText.bodyDim),
                        ],
                      ),
                    );
                  },
                ),
        ),

        const _Actions(),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 結果頁底下的兩顆按鈕。
///
/// 做滿今天的份量就只剩回首頁，不留「再來一輪」讓人硬做。
/// 那條上限本來就是拿來擋自己的。
class _Actions extends ConsumerWidget {
  const _Actions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeStateProvider);
    final blocked = home.valueOrNull?.limitReached ?? false;

    final back = OutlinedButton(
      onPressed: () => context.go('/home'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink2,
        side: const BorderSide(color: AppColors.glassEdge),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
        ),
      ),
      child: const Text('回首頁'),
    );

    if (blocked) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: back),
          const SizedBox(height: Gap.sm),
          const Text('今天的份量做完了', style: AppText.note),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: back),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: FilledButton(
            onPressed: () {
              // 換成新的一輪，不要把結果頁疊在後面。
              ref.invalidate(quizControllerProvider);
              context.pushReplacement('/quiz');
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentSolid,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.button),
              ),
            ),
            child: const Text('再來一輪'),
          ),
        ),
      ],
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

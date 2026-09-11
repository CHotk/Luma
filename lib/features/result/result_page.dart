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
            child: result == null
                ? const Center(child: Text('這輪沒有紀錄', style: AppText.bodyDim))
                : _Body(result: result),
          ),
        ),
      ),
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

        FilledButton(
          onPressed: () => context.go('/home'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.glassFill,
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.button),
            ),
          ),
          child: const Text('回首頁'),
        ),
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

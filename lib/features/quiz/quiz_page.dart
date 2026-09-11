import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/quiz.dart';
import '../../domain/spell_judge.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import 'quiz_controller.dart';

/// 測驗頁。
///
/// 版型 04 這頁沒有計時器：時間照樣在背後記，但不顯示，
/// 顯示秒數會讓人急著答，測出來的東西就不準了。
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key});

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _answer(bool correct) async {
    final done = await ref
        .read(quizControllerProvider.notifier)
        .answer(correct);
    _input.clear();
    if (done && mounted) context.pushReplacement('/result');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quizControllerProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) =>
                  Center(child: Text('出題失敗：$e', style: AppText.bodyDim)),
              data: (s) => Column(
                children: [
                  const SizedBox(height: Gap.md),
                  _ProgressBar(state: s),
                  const SizedBox(height: Gap.md),
                  Expanded(
                    child: s.current.mode == QuizMode.tap
                        ? _TapCard(state: s)
                        : _TypeCard(state: s, controller: _input),
                  ),
                  const SizedBox(height: Gap.md),
                  _Actions(state: s, onAnswer: _answer, input: _input),
                  const SizedBox(height: Gap.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 考到一半要能走。答過的題目在作答當下就寫進紀錄了，離開不會掉。
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close, size: 19),
          color: AppColors.ink3,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: '離開這輪',
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 4,
              backgroundColor: AppColors.glassEdge,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        Text(
          '${state.index + 1} / ${state.questions.length}',
          style: AppText.note,
        ),
      ],
    );
  }
}

/// 英翻中：正面英文，點一下翻出中文。
class _TapCard extends ConsumerWidget {
  const _TapCard({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = state.current.word;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(22),
      onTap: () => ref.read(quizControllerProvider.notifier).toggleReveal(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: state.revealed
              ? [
                  Text(word.zh, style: AppText.hero.copyWith(fontSize: 30)),
                  const SizedBox(height: Gap.xs),
                  Text(word.pos, style: AppText.note),
                ]
              : [
                  const Text('想一下，點卡片看答案', style: AppText.note),
                  const SizedBox(height: Gap.sm),
                  Text(word.word, style: AppText.hero),
                  const SizedBox(height: Gap.xs),
                  Text(word.pos, style: AppText.note),
                ],
        ),
      ),
    );
  }
}

/// 中翻英：看中文把英文打出來。唯一測得到拼寫的題型。
class _TypeCard extends ConsumerWidget {
  const _TypeCard({required this.state, required this.controller});

  final QuizState state;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = state.current.word;
    final judged = state.judged;

    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(word.zh, style: AppText.hero.copyWith(fontSize: 28)),
            const SizedBox(height: Gap.sm),
            Text(
              SpellJudge.mask(word.word),
              style: const TextStyle(
                fontSize: 15,
                letterSpacing: 5,
                color: AppColors.ink2,
              ),
            ),
            const SizedBox(height: Gap.lg),
            TextField(
              controller: controller,
              enabled: judged == null,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              decoration: InputDecoration(
                hintText: '打出英文',
                hintStyle: const TextStyle(color: AppColors.ink3),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: AppColors.glassEdge),
                ),
              ),
              onChanged: ref.read(quizControllerProvider.notifier).updateInput,
              onSubmitted: (_) =>
                  ref.read(quizControllerProvider.notifier).submitTyped(),
            ),
            const SizedBox(height: Gap.md),
            SizedBox(
              height: 20,
              child: judged == null
                  ? null
                  : Text(
                      judged
                          ? '對了'
                          : controller.text.trim().isEmpty
                          ? '答案是 ${word.word}'
                          : '不對，答案是 ${word.word}',
                      style: TextStyle(
                        fontSize: 13,
                        color: judged ? AppColors.ok : AppColors.bad,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底下的按鈕。點選題是兩顆，打字題是一顆。
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.state,
    required this.onAnswer,
    required this.input,
  });

  final QuizState state;
  final Future<void> Function(bool) onAnswer;
  final TextEditingController input;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.current.mode == QuizMode.type) {
      final judged = state.judged;

      // 判完之後只剩一顆「下一題」，不要留著讓人誤按。
      if (judged != null) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onAnswer(judged),
            style: _filled,
            child: const Text('下一題'),
          ),
        );
      }

      // 還沒判定：打不出來就按「不會」，不要逼人硬湊一個錯的上去。
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  ref.read(quizControllerProvider.notifier).giveUp(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.bad,
                side: const BorderSide(color: AppColors.glassEdge),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.button),
                ),
              ),
              child: const Text('不會'),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: FilledButton(
              onPressed: () =>
                  ref.read(quizControllerProvider.notifier).submitTyped(),
              style: _filled,
              child: const Text('送出'),
            ),
          ),
        ],
      );
    }

    // 兩顆都隨時能按（使用者 2026-09-11 決定）。
    // 不知道就是不知道，知道也不用先翻開才准說知道，
    // 翻不翻由自己決定，不要拿流程卡人。
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => onAnswer(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.bad,
              side: const BorderSide(color: AppColors.glassEdge),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.button),
              ),
            ),
            child: const Text('不會'),
          ),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: FilledButton(
            onPressed: () => onAnswer(true),
            style: _filled,
            child: const Text('會'),
          ),
        ),
      ],
    );
  }

  static final _filled = FilledButton.styleFrom(
    backgroundColor: AppColors.accentSolid,
    disabledBackgroundColor: AppColors.glassFill,
    disabledForegroundColor: AppColors.ink3,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.button),
    ),
  );
}

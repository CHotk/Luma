import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/rules_config.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import 'settings_controller.dart';

/// 設定。改完立即生效，不用按確定。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settingsControllerProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
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
                    const Text('設定', style: AppText.title),
                  ],
                ),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到設定：$e', style: AppText.bodyDim)),
                    data: (rules) => _Body(rules: rules),
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

class _Body extends ConsumerWidget {
  const _Body({required this.rules});

  final RulesConfig rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void save(RulesConfig next) =>
        ref.read(settingsControllerProvider.notifier).apply(next);

    return ListView(
      children: [
        const _SectionLabel('題型'),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final style in QuizStyle.values)
                _StyleRow(
                  style: style,
                  selected: rules.quizStyle == style,
                  onTap: () => save(rules.copyWith(quizStyle: style)),
                ),
            ],
          ),
        ),

        if (rules.quizStyle == QuizStyle.mixed) ...[
          const SizedBox(height: Gap.sm),
          GlassCard(
            child: _Stepper(
              title: '一輪幾題要打字',
              note: '其餘都是點選題',
              value: '${rules.typeQuestions} 題',
              onMinus: rules.typeQuestions > 1
                  ? () => save(
                      rules.copyWith(typeQuestions: rules.typeQuestions - 1),
                    )
                  : null,
              onPlus: rules.typeQuestions < rules.questionsPerRound
                  ? () => save(
                      rules.copyWith(typeQuestions: rules.typeQuestions + 1),
                    )
                  : null,
            ),
          ),
        ],

        const SizedBox(height: Gap.lg),
        const _SectionLabel('每天的份量'),
        GlassCard(
          child: Column(
            children: [
              _Stepper(
                title: '每天最多幾輪',
                note: '做滿就擋住，偽裝模式不受限',
                value: '${rules.roundsPerDay} 輪',
                onMinus: rules.roundsPerDay > 1
                    ? () => save(
                        rules.copyWith(roundsPerDay: rules.roundsPerDay - 1),
                      )
                    : null,
                onPlus: rules.roundsPerDay < 20
                    ? () => save(
                        rules.copyWith(roundsPerDay: rules.roundsPerDay + 1),
                      )
                    : null,
              ),
              const _Hair(),
              _Stepper(
                title: '每天最多幾分鐘',
                note: '跟輪數哪個先到算哪個',
                value: '${rules.minutesPerDay} 分',
                onMinus: rules.minutesPerDay > 5
                    ? () => save(
                        rules.copyWith(minutesPerDay: rules.minutesPerDay - 5),
                      )
                    : null,
                onPlus: rules.minutesPerDay < 120
                    ? () => save(
                        rules.copyWith(minutesPerDay: rules.minutesPerDay + 5),
                      )
                    : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),
        const _SectionLabel('判定'),
        GlassCard(
          child: Column(
            children: [
              _Stepper(
                title: '沒錯過的字要答對幾次算掌握',
                note: '從頭到尾沒錯過才走這條',
                value: '${rules.confirmRight} 次',
                onMinus: rules.confirmRight > 1
                    ? () => save(
                        rules.copyWith(confirmRight: rules.confirmRight - 1),
                      )
                    : null,
                onPlus: rules.confirmRight < 5
                    ? () => save(
                        rules.copyWith(confirmRight: rules.confirmRight + 1),
                      )
                    : null,
              ),
              const _Hair(),
              _Stepper(
                title: '錯過的字要答對幾倍才算掌握',
                note:
                    '錯 1 次要答對 ${rules.recoveryRatio} 次，'
                    '錯 5 次就要 ${rules.recoveryRatio * 5} 次',
                value: '${rules.recoveryRatio} 倍',
                onMinus: rules.recoveryRatio > 1
                    ? () => save(
                        rules.copyWith(recoveryRatio: rules.recoveryRatio - 1),
                      )
                    : null,
                onPlus: rules.recoveryRatio < 30
                    ? () => save(
                        rules.copyWith(recoveryRatio: rules.recoveryRatio + 1),
                      )
                    : null,
              ),
              const _Hair(),
              _Stepper(
                title: '每輪答錯過的字',
                note: '從出題數裡挪出來，錯最多次的先回來',
                value: '${rules.pendingPerRound} 題',
                onMinus: rules.pendingPerRound > 0
                    ? () => save(
                        rules.copyWith(
                          pendingPerRound: rules.pendingPerRound - 1,
                        ),
                      )
                    : null,
                onPlus: rules.pendingPerRound < rules.newPerRound
                    ? () => save(
                        rules.copyWith(
                          pendingPerRound: rules.pendingPerRound + 1,
                        ),
                      )
                    : null,
              ),
              const _Hair(),
              _Stepper(
                title: '每輪出題數',
                note:
                    '新字 ${rules.freshPerRound} 加待複習 ${rules.pendingPerRound}，'
                    '另外回考 ${rules.reviewPerRound} 個',
                value: '${rules.newPerRound} 題',
                onMinus: rules.newPerRound > 3
                    ? () => save(
                        rules.copyWith(newPerRound: rules.newPerRound - 1),
                      )
                    : null,
                onPlus: rules.newPerRound < 20
                    ? () => save(
                        rules.copyWith(newPerRound: rules.newPerRound + 1),
                      )
                    : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.md),
        Text(
          '一輪共 ${rules.questionsPerRound} 題。'
          '拼字判定不管大小寫，複數算錯，a 和 an 算不同的字。',
          textAlign: TextAlign.center,
          style: AppText.note,
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: Gap.sm),
    child: Text(text, style: AppText.label),
  );
}

/// 題型選項。整列都可以點，不要只有小圓點能點。
class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final QuizStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AppColors.accent : AppColors.ink3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    style.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.ink : AppColors.ink2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(style.description, style: AppText.note),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加減一個數字。到邊界就把按鈕變灰，不要讓人按了沒反應。
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.note = '',
  });

  final String title;
  final String note;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(note, style: AppText.note),
                ],
              ],
            ),
          ),
          _Round(icon: Icons.remove, onTap: onMinus),
          SizedBox(
            width: 58,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.accent,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _Round(icon: Icons.add, onTap: onPlus),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: Icon(
          icon,
          size: 15,
          color: enabled ? AppColors.ink : AppColors.ink3,
        ),
      ),
    );
  }
}

class _Hair extends StatelessWidget {
  const _Hair();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.glassEdge);
}

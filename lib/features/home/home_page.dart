import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/ring_progress.dart';
import 'home_controller.dart';

/// 首頁。版型 04 節制版：圓環是主角，其餘都讓路。
///
/// 這個畫面只排版，所有數字都由 [homeStateProvider] 算好送進來。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeStateProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) => Center(
                child: Text('讀不到資料：$e', style: AppText.bodyDim),
              ),
              data: (s) => _Body(state: s),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final minutesUsed = state.usage.practiceSeconds ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Gap.md),
        const _TopBar(),
        const SizedBox(height: Gap.lg),

        GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
          child: Column(
            children: [
              RingProgress(
                done: state.usage.roundsDone,
                total: state.rules.roundsPerDay,
                centerLabel:
                    '${state.usage.roundsDone}/${state.rules.roundsPerDay}',
                bottomLabel: '$minutesUsed / ${state.rules.minutesPerDay} 分',
              ),
              const SizedBox(height: Gap.sm),
              Text(
                state.limitReached ? '今天的份量做完了' : '做滿就停，明天再來',
                style: AppText.bodyDim,
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelLabel('下一輪'),
              const SizedBox(height: Gap.sm),
              _Row('沒考過的新字', '${state.rules.newPerRound}'),
              _Row('回考已答對過的字', '${state.rules.reviewPerRound}'),
              _Row('要打字的題數', '${state.rules.typeQuestions}'),
            ],
          ),
        ),

        const Spacer(),
        _StartButton(state: state),
        const SizedBox(height: Gap.sm),
        Text(
          state.limitReached
              ? '明天早上再來'
              : '做完這輪還剩 ${state.roundsLeft - 1} 輪',
          textAlign: TextAlign.center,
          style: AppText.note,
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// 首頁頂端。左邊標題，右邊兩個入口。
///
/// 偽裝模式放在最右邊，因為需要用到的時候通常很急。
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Text('今天', style: AppText.title),
        const Spacer(),
        IconButton(
          onPressed: () => context.push('/library'),
          icon: const Icon(Icons.menu_book_rounded, size: 20),
          color: AppColors.ink2,
          tooltip: '單字庫',
        ),
        IconButton(
          onPressed: () => context.push('/history'),
          icon: const Icon(Icons.bar_chart_rounded, size: 20),
          color: AppColors.ink2,
          tooltip: '總紀錄',
        ),
        IconButton(
          onPressed: () {
            // 進偽裝模式前先掀旗標，出題時才知道不要出打字題。
            ref.read(stealthModeProvider.notifier).state = true;
            context.push('/stealth');
          },
          icon: const Icon(Icons.terminal_rounded, size: 20),
          color: AppColors.ink2,
          tooltip: '偽裝模式',
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

/// 做滿上限就真的按不下去。這是防放棄機制的核心，不要改成只跳提示。
class _StartButton extends ConsumerWidget {
  const _StartButton({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = state.limitReached;
    return FilledButton(
      onPressed: blocked
          ? null
          : () {
              // 從首頁走一般流程，確保上一次的偽裝旗標不會殘留。
              ref.read(stealthModeProvider.notifier).state = false;
              context.push('/quiz');
            },
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentSolid,
        disabledBackgroundColor: AppColors.glassFill,
        disabledForegroundColor: AppColors.ink3,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
        ),
      ),
      child: Text(
        blocked ? '今天做完了' : '開始這輪',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

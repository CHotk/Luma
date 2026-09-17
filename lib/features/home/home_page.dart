import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/encouragement.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/mini_flag.dart';
import '../../shared/widgets/ring_progress.dart';
import 'home_controller.dart';

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 週幾要跟著 [HomeState.usage] 的日期算，不用 DateTime.now()，
/// 這樣測試跟畫面看到的「今天」才是同一天。
String _weekdayLabel(DateTime date) => '週${_weekdayLabels[date.weekday - 1]}';

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
              error: (e, _) =>
                  Center(child: Text('讀不到資料：$e', style: AppText.bodyDim)),
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
        _TopBar(date: state.usage.date),
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
                // 做滿了就講做滿了，其餘時候給一句每天不一樣的話。
                state.limitReached
                    ? '今天的份量做完了'
                    : Encouragement.forDate(state.usage.date),
                textAlign: TextAlign.center,
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
              _Row('待複習', '${state.rules.pendingPerRound}'),
              _Row('新字', '${state.rules.freshPerRound}'),
              _Row('已掌握', '${state.rules.masteredPerRound}'),

              if (state.rules.effectiveTypeQuestions > 0)
                _Row('要打字的題數', '${state.rules.effectiveTypeQuestions}'),
            ],
          ),
        ),

        const Spacer(),
        _StartButton(state: state),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// 首頁頂端。左邊週幾＋國旗，右邊功能入口。
///
/// 國旗表示現在練的是哪個語言的軌道（目前只有英文），之後日文版面
/// 上線就換一面日本國旗，同一顆 [MiniFlag] 換參數就好。
/// 偽裝模式放在最右邊，因為需要用到的時候通常很急。
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // IconButton 預設的點擊區是 48 見方，五顆排在一起會超出手機寬度，
    // 最右邊那顆就被擠不見。這裡改成 36 並清掉內距。
    final entries = <({IconData icon, String tip, VoidCallback tap})>[
      (
        icon: Icons.tips_and_updates_outlined,
        tip: '用法地雷',
        tap: () => context.push('/notes'),
      ),
      (
        icon: Icons.menu_book_rounded,
        tip: '單字庫',
        tap: () => context.push('/library'),
      ),
      // 暫時的入口：日文軌道還沒有自己的首頁，先讓五十音手寫練習頁
      // 掛在這裡能被點到。等日文首頁做出來，這顆要移過去，不留在這。
      (
        icon: Icons.brush_outlined,
        tip: '假名練習（暫）',
        tap: () => context.push('/kana-practice'),
      ),
      (
        icon: Icons.bar_chart_rounded,
        tip: '總紀錄',
        tap: () => context.push('/history'),
      ),
      (
        icon: Icons.terminal_rounded,
        tip: '偽裝模式',
        tap: () {
          // 進偽裝模式前先掀旗標，出題時才知道要強制點選題。
          ref.read(stealthModeProvider.notifier).state = true;
          context.push('/stealth');
        },
      ),
      (
        icon: Icons.settings_outlined,
        tip: '設定',
        tap: () => context.push('/settings'),
      ),
    ];

    return Row(
      children: [
        Text(_weekdayLabel(date), style: AppText.title),
        const SizedBox(width: Gap.sm),
        const MiniFlag(country: FlagCountry.us),
        const Spacer(),
        for (final e in entries)
          IconButton(
            onPressed: e.tap,
            icon: Icon(e.icon, size: 20),
            color: AppColors.ink2,
            tooltip: e.tip,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

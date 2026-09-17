import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/encouragement.dart';
import '../../domain/time_of_day_label.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/ring_progress.dart';
import '../../shared/widgets/track_switcher.dart';
import '../kana_practice/gojuon_data.dart';
import 'jp_home_controller.dart';

/// 日文軌道的首頁。配色是設計稿定案的「櫻」（見 `design-history/`），
/// 版面骨架照設計稿的三塊卡片：進度環、五十音手寫練習預覽、下一輪
/// 清單——只換 [AmbientBackground] 的底色跟四團模糊色塊，`GlassCard`
/// 本身不用換色，設計稿裡玻璃面板一直是中性的白霧感。
///
/// 進度環跟下一輪清單的數字都是真資料：[jpHomeStateProvider] 用
/// [JpReviewConfig] 那套簡化複習排程，從 [KanaPracticeEntry] 紀錄
/// 算出今天練了幾個字、待複習/新字/已掌握各幾個——不是設計稿裡的
/// 範例數字（使用者 2026-09-17 決定要有這套排程，不然這兩塊只能
/// 編數字，違反這個專案「不顯示假資料」的規矩）。
class JpHomePage extends ConsumerWidget {
  const JpHomePage({super.key});

  static const _accent = Color(0xFFEA92AC);
  static const _amb = [
    Color(0xFF4A2036),
    Color(0xFF6B3550),
    Color(0xFF2E2440),
    Color(0xFF7A3F55),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jpHomeStateProvider);

    return Scaffold(
      body: AmbientBackground(
        background: const Color(0xFF1B1420),
        blobColors: _amb,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) =>
                  Center(child: Text('讀不到資料：$e', style: AppText.bodyDim)),
              data: (state) => _Body(state: state),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final JpHomeState state;

  @override
  Widget build(BuildContext context) {
    final target = state.config.dailyKanaTarget;
    final done = state.todayCount >= target;

    // 跟英文首頁同一個問題：Column 直接放 Spacer() 沒有滾動能力，螢幕
    // 矮一點就整頁卡死，滾輪／手指滑動都沒反應。用 LayoutBuilder 量出
    // 可用高度，塞得下維持原排版（按鈕釘底部），塞不下就讓
    // SingleChildScrollView 接手滾動。
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.md),
                  _TopBar(now: DateTime.now()),
                  const SizedBox(height: Gap.lg),

                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
                    child: Column(
                      children: [
                        RingProgress(
                          done: state.todayCount,
                          total: target,
                          centerLabel: '${state.todayCount}/$target',
                          bottomLabel:
                              '${state.todayMinutes} / ${state.config.dailyMinutesTarget} 分',
                        ),
                        const SizedBox(height: Gap.sm),
                        Text(
                          done
                              ? '今天的份量做完了'
                              : Encouragement.forDate(DateTime.now()),
                          textAlign: TextAlign.center,
                          style: AppText.bodyDim,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Gap.md),
                  const GlassCard(child: _KanaPreview()),

                  const SizedBox(height: Gap.md),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PanelLabel('下一輪'),
                        const SizedBox(height: Gap.sm),
                        _Row('待複習', '${state.review.due}'),
                        _Row('新字', '${state.review.fresh}'),
                        _Row('已掌握', '${state.review.mastered}'),
                        _Row('手寫練習', '$target 字'),
                      ],
                    ),
                  ),

                  const Spacer(),
                  FilledButton(
                    onPressed: () => context.push('/kana-practice'),
                    style: FilledButton.styleFrom(
                      backgroundColor: JpHomePage._accent,
                      foregroundColor: const Color(0xFF241019),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.button),
                      ),
                    ),
                    child: const Text(
                      '開始這輪',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 首頁頂端。左邊週幾＋時間＋時段 emoji，中間是語言軌道切換，右邊只留
/// 對日文軌道真的有意義的入口——英文軌道那幾顆（單字庫／總紀錄／
/// 偽裝模式）指向的都是英文單字資料，搬到這裡點了也是空的或誤導，
/// 所以不放；設定頁是全 App 共用的，留著。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${weekdayLabel(now)} ${clockLabel(now)} ${periodEmoji(now)}',
          style: AppText.title,
        ),
        const SizedBox(width: Gap.sm),
        const TrackSwitcher(current: LearningTrack.ja),
        const Spacer(),
        IconButton(
          onPressed: () => context.push('/kana-practice/history'),
          icon: const Icon(Icons.history, size: 20),
          color: AppColors.ink2,
          tooltip: '練習紀錄',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined, size: 20),
          color: AppColors.ink2,
          tooltip: '設定',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }
}

/// 五十音手寫練習的預覽：選行、選字，右側是描摹格的縮小預覽。
/// 這裡選的字只是預覽用，不會帶到真正的練習頁——那頁本來就有自己
/// 一套選字狀態，這張卡片單純是「進去之前先看一眼」。
class _KanaPreview extends StatefulWidget {
  const _KanaPreview();

  @override
  State<_KanaPreview> createState() => _KanaPreviewState();
}

class _KanaPreviewState extends State<_KanaPreview> {
  String _row = gojuonRows.keys.first;
  (String, String) _selected = gojuonRows.values.first.first;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PanelLabel('五十音・手寫練習'),
        const SizedBox(height: Gap.sm),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: gojuonRows.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final row = gojuonRows.keys.elementAt(i);
              return _PreviewChip(
                label: row,
                selected: row == _row,
                onTap: () => setState(() {
                  _row = row;
                  _selected = gojuonRows[row]!.first;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final pair in gojuonRows[_row]!)
              _PreviewChip(
                label: pair.$1,
                selected: pair == _selected,
                onTap: () => setState(() => _selected = pair),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                border: Border.all(color: AppColors.glassEdge),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _selected.$1,
                style: const TextStyle(
                  fontSize: 42,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selected.$2,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('點進去可以真的用手指或滑鼠寫這個字', style: AppText.note),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? JpHomePage._accent.withValues(alpha: 0.28)
              : AppColors.glassFill,
          border: Border.all(
            color: selected
                ? JpHomePage._accent.withValues(alpha: 0.6)
                : AppColors.glassEdge,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.ink : AppColors.ink2,
          ),
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

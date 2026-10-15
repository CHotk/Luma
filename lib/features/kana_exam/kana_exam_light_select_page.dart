import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../jp_light/jp_light_data.dart';
import '../kana_practice/gojuon_data.dart';
import 'kana_exam_header_bar.dart';

/// 「點亮」考試選範圍（2026-10-15 使用者要求：考試多一個點亮模式，範圍
/// 從複選變單選）：一次只選一行，全部答對那一行就開花（見
/// `jp_light_data.dart`）。每一行旁邊標開了沒、最好幾 %。
class KanaExamLightSelectPage extends ConsumerStatefulWidget {
  const KanaExamLightSelectPage({super.key});

  @override
  ConsumerState<KanaExamLightSelectPage> createState() =>
      _KanaExamLightSelectPageState();
}

class _KanaExamLightSelectPageState
    extends ConsumerState<KanaExamLightSelectPage> {
  String? _row;

  @override
  Widget build(BuildContext context) {
    final lights = {
      for (final l in ref.watch(jpLightProvider).valueOrNull ?? const [])
        l.row: l,
    };
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
                const KanaExamHeaderBar(title: '🌸 點亮'),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '選一行，平假片假隨機出，全部答對就點亮那一行的櫻花。',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.ink2,
                          height: 1.5,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/jp-light'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.jpAccent,
                      ),
                      child: const Text('看櫻花樹'),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: ListView(
                    children: [
                      for (final row in gojuonRows.keys)
                        _LightRowTile(
                          row: row,
                          light: lights[row],
                          selected: _row == row,
                          onTap: () => setState(() => _row = row),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                FilledButton(
                  onPressed: _row == null
                      ? null
                      : () => context.push('/kana-exam/start', extra: _row),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.jpAccent,
                    foregroundColor: AppColors.jpAccentInk,
                    disabledBackgroundColor: AppColors.glassFill,
                    disabledForegroundColor: AppColors.ink3,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.button),
                    ),
                  ),
                  child: Text(
                    _row == null
                        ? '選一行開始'
                        : '開始點亮 $_row行（${gojuonRows[_row]!.length} 題）',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LightRowTile extends StatelessWidget {
  const _LightRowTile({
    required this.row,
    required this.light,
    required this.selected,
    required this.onTap,
  });

  final String row;
  final JpRowLight? light;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kana = gojuonRows[row]!.map((k) => k.$1).join(' ');
    final l = light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.jpAccent.withValues(alpha: 0.16)
                : AppColors.glassFill,
            border: Border.all(
              color: selected
                  ? AppColors.jpAccent.withValues(alpha: 0.7)
                  : AppColors.glassEdge,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.jpAccent : AppColors.ink3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kana,
                  style: const TextStyle(
                    fontSize: 16,
                    letterSpacing: 2,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (l != null && l.lit)
                const Text(
                  '🌸 已點亮',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.jpAccent,
                  ),
                )
              else if (l != null && l.exams > 0)
                Text(
                  '最好 ${l.best}%',
                  style: TextStyle(fontSize: 12, color: AppColors.ink3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

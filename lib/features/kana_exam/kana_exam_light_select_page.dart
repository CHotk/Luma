import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_bottom_nav.dart' show FloatingNavInset;
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
///
/// 2026-10-16 使用者要求：只能照五十音順序點亮，後面的行鎖住；點亮哪一行
/// 都要從あ考到那一行、平假片假都考（[jpLightExamRows]）。預設選好輪到
/// 的那一行。
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
    final list = ref.watch(jpLightProvider).valueOrNull ?? const [];
    final lights = {for (final l in list) l.row: l};
    final next = jpNextLightRow(list);
    final row = _row ?? next;
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
                        '照順序一行一行點亮：從あ考到這一行，平假片假都考，全部答對就開花。',
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
                      for (final r in gojuonRows.keys)
                        _LightRowTile(
                          row: r,
                          light: lights[r],
                          selected: row == r,
                          lockedBy: list.isEmpty || jpCanLight(list, r)
                              ? null
                              : next,
                          onTap: () => setState(() => _row = r),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                FilledButton(
                  onPressed: row == null
                      ? null
                      : () => context.push('/kana-exam/start', extra: row),
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
                    row == null
                        ? '選一行開始'
                        : '開始點亮 $row行（${jpLightExamSize(row)} 題）',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // 底部日文分頁列浮在上面（2026-10-15），按鈕不要被擋住。
                SizedBox(height: Gap.lg + FloatingNavInset.of(context)),
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
    required this.lockedBy,
    required this.onTap,
  });

  /// 還沒輪到：要先點亮的那一行；能考是 null。
  final String? lockedBy;

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
        onTap: lockedBy == null ? onTap : null,
        child: Opacity(
          opacity: lockedBy == null ? 1 : 0.45,
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
                if (lockedBy != null)
                  Text(
                    '🔒 先點亮 $lockedBy行',
                    style: TextStyle(fontSize: 12, color: AppColors.ink3),
                  )
                else if (l != null && l.lit)
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
      ),
    );
  }
}

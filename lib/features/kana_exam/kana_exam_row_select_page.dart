import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../shared/widgets/ambient_background.dart';
import '../kana_practice/gojuon_data.dart';
import 'kana_exam_header_bar.dart';
import 'kana_exam_page.dart';

/// 50 音考試的選題範圍頁：勾選要考哪幾行（あ／か／さ……），出的題目
/// 只會從勾選的行裡挑字。平假名／片假名不用另外選，出題時每題各自
/// 隨機決定用哪一種——兩份表行跟羅馬字都一一對應，混著考才是真正
/// 考熟不熟，不是考「認不認得某一種字體」（2026-09-21 使用者要求：
/// 剩下要考系列中哪一個、平假還是片假都無所謂）。
class KanaExamRowSelectPage extends StatefulWidget {
  const KanaExamRowSelectPage({super.key});

  @override
  State<KanaExamRowSelectPage> createState() => _KanaExamRowSelectPageState();
}

class _KanaExamRowSelectPageState extends State<KanaExamRowSelectPage> {
  final Set<String> _selectedRows = {...gojuonRows.keys};

  void _toggleRow(String row) {
    setState(() {
      if (_selectedRows.contains(row)) {
        _selectedRows.remove(row);
      } else {
        _selectedRows.add(row);
      }
    });
  }

  void _selectAll() => setState(
    () => _selectedRows
      ..clear()
      ..addAll(gojuonRows.keys),
  );

  // 全部取消是合法狀態（不像單獨取消一行時要防呆），只是這樣就沒東西
  // 可以考——靠「開始考試」按鈕在 [_selectedRows] 是空的時候 disable
  // 掉來擋，不是在這裡不准使用者清空（2026-09-21 使用者要求：有全選
  // 就要有全取消）。
  void _selectNone() => setState(_selectedRows.clear);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                const KanaExamHeaderBar(title: '選出題範圍'),
                const SizedBox(height: Gap.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '勾選要考的行，題目只從勾選的範圍出。寫不出來時可以按\n'
                    '「不會」跳過，不用硬湊答案。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink2,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    Text(
                      '已選 ${_selectedRows.length} / ${gojuonRows.length} 行',
                      style: TextStyle(fontSize: 13, color: AppColors.ink3),
                    ),
                    const Spacer(),
                    // 一般使用習慣是「全選」在左、「全取消」在右（正向
                    // 操作在前，取消/清空這種收斂動作在後）——原本兩顆
                    // 位置反了（2026-09-22 使用者回饋）。
                    TextButton(
                      onPressed: _selectAll,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.jpAccent,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('全選'),
                    ),
                    const SizedBox(width: Gap.sm),
                    TextButton(
                      onPressed: _selectNone,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.ink2,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('全取消'),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final row in gojuonRows.keys)
                          _RowCard(
                            row: row,
                            kanaList: gojuonRows[row]!,
                            selected: _selectedRows.contains(row),
                            onTap: () => _toggleRow(row),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    // 一行都沒選就沒東西可以考，擋在這裡不讓按下去
                    // （2026-09-21 使用者要求：全取消是合法操作，但
                    // 要有東西擋著不能真的空題庫開始考試）。
                    onPressed: _selectedRows.isEmpty
                        ? null
                        : () => context.push(
                            '/kana-exam/start',
                            extra: (
                              ExamMode.kana,
                              Set<String>.of(_selectedRows),
                            ),
                          ),
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
                    child: const Text(
                      '開始考試',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
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

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.row,
    required this.kanaList,
    required this.selected,
    required this.onTap,
  });

  final String row;
  final List<(String kana, String romaji)> kanaList;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width =
        (MediaQuery.of(context).size.width - Gap.screenSide * 2 - 10) / 2;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: width.clamp(140, 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.jpAccent.withValues(alpha: 0.16)
              : AppColors.glassFill,
          border: Border.all(
            color: selected
                ? AppColors.jpAccent.withValues(alpha: 0.6)
                : AppColors.glassEdge,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: selected ? AppColors.jpAccent : AppColors.ink3,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$row行',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.ink : AppColors.ink2,
                    ),
                  ),
                  Text(
                    kanaList.map((e) => e.$1).join(' '),
                    style: TextStyle(fontSize: 11, color: AppColors.ink3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../kana_practice/kana_paper.dart';

/// 考試結果彈窗。
///
/// 還沒有手寫辨識，系統沒辦法自動判斷寫得對不對，所以「提交」按下去
/// 不會自動算答對——彈窗把「你寫的」跟「正確答案」重播出來並排放，
/// 由使用者自己核對，按「✓ 我寫對了」或「✗ 我寫錯了」才真正記錄
/// 這一題的結果（2026-09-21 使用者要求：不是按提交就等於答對）。
///
/// [knownIncorrect] 為 true 時（按了「不會」進來的），已經確定是答錯，
/// 不用再讓使用者自評，只顯示答案跟「下一題」。
void showExamResultDialog({
  required BuildContext context,
  required List<List<Offset>> userStrokes,
  required String correctAnswer,
  required bool knownIncorrect,
  required void Function(bool isCorrect) onFinish,
  bool isKatakana = false,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (context) => ExamResultDialog(
      userStrokes: userStrokes,
      correctAnswer: correctAnswer,
      knownIncorrect: knownIncorrect,
      onFinish: onFinish,
      isKatakana: isKatakana,
    ),
  );
}

class ExamResultDialog extends StatelessWidget {
  const ExamResultDialog({
    required this.userStrokes,
    required this.correctAnswer,
    required this.knownIncorrect,
    required this.onFinish,
    this.isKatakana = false,
    super.key,
  });

  /// 使用者剛剛寫的筆畫（正規化座標），直接重播出來給使用者自己核對
  /// ——還沒有手寫辨識，沒辦法把筆畫轉成文字放進對比欄，畫出來才誠實
  /// （2026-09-21）。
  final List<List<Offset>> userStrokes;
  final String correctAnswer;
  final bool knownIncorrect;
  final void Function(bool isCorrect) onFinish;

  /// 正確答案是不是片假名，只影響「正確答案」文字的顏色，跟考試頁的
  /// [_ScriptBadge] 用同一組配色，看習慣了哪個顏色代表哪種字體，答案
  /// 揭曉時也要一致，不然使用者又要重新判斷一次（2026-09-21）。
  final bool isKatakana;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.jpAccent.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (knownIncorrect) ...[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.bad.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Center(
                  child: Text(
                    '✕',
                    style: TextStyle(
                      fontSize: 48,
                      color: AppColors.bad,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              const Text('公布答案', style: AppText.title),
              const SizedBox(height: Gap.xs),
              Text(
                '下次再試試看',
                style: TextStyle(fontSize: 14, color: AppColors.ink2),
              ),
            ] else ...[
              const Text('自己核對一下', style: AppText.title),
              const SizedBox(height: Gap.xs),
              Text(
                '你寫的字對不對，自己判斷',
                style: TextStyle(fontSize: 14, color: AppColors.ink2),
              ),
            ],
            const SizedBox(height: Gap.lg),

            // 對比區
            Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                border: Border.all(color: AppColors.glassEdge),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // 使用者剛寫的字，直接重播筆畫（還沒有辨識能力，不能
                  // 顯示成文字，見上面欄位說明）。
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '你寫的',
                          style: TextStyle(fontSize: 12, color: AppColors.ink3),
                        ),
                        const SizedBox(height: Gap.xs),
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: paperColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: CustomPaint(
                            size: const Size(72, 72),
                            painter: InkPainter(
                              strokes: userStrokes,
                              strokeWidth: inkStrokeWidth(72),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 分隔線
                  SizedBox(
                    height: 80,
                    child: VerticalDivider(
                      color: AppColors.glassEdge,
                      thickness: 1,
                    ),
                  ),

                  // 正確答案
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '正確答案',
                          style: TextStyle(fontSize: 12, color: AppColors.ink3),
                        ),
                        const SizedBox(height: Gap.xs),
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: Center(
                            child: Text(
                              correctAnswer,
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: isKatakana
                                    ? AppColors.accent
                                    : AppColors.jpAccent,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),

            // 按鈕：已知答錯（按了不會）就只有下一題；否則讓使用者自評。
            if (knownIncorrect)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onFinish(false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.jpAccent,
                    foregroundColor: AppColors.jpAccentInk,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    '下一題',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onFinish(false);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.bad,
                        side: const BorderSide(color: AppColors.bad),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '✗ 寫錯了',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onFinish(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ok,
                        foregroundColor: AppColors.jpAccentInk,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '✓ 寫對了',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

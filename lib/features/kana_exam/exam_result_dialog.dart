import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../kana_practice/kana_paper.dart';

/// 考試結果彈窗。
void showExamResultDialog({
  required BuildContext context,
  required bool isCorrect,
  required List<List<Offset>> userStrokes,
  required String correctAnswer,
  required VoidCallback onNext,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => ExamResultDialog(
      isCorrect: isCorrect,
      userStrokes: userStrokes,
      correctAnswer: correctAnswer,
      onNext: onNext,
    ),
  );
}

class ExamResultDialog extends StatelessWidget {
  const ExamResultDialog({
    required this.isCorrect,
    required this.userStrokes,
    required this.correctAnswer,
    required this.onNext,
    super.key,
  });

  final bool isCorrect;

  /// 使用者剛剛寫的筆畫（正規化座標），直接重播出來給使用者自己核對
  /// ——還沒有手寫辨識，沒辦法把筆畫轉成文字放進對比欄，畫出來才誠實
  /// （2026-09-21）。
  final List<List<Offset>> userStrokes;
  final String correctAnswer;
  final VoidCallback onNext;

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
            // 結果圖標
            if (isCorrect)
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.ok.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Center(
                  child: Text(
                    '✓',
                    style: TextStyle(
                      fontSize: 48,
                      color: AppColors.ok,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else
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

            // 標題
            Text(isCorrect ? '完美！' : '再試一次', style: AppText.title),
            const SizedBox(height: Gap.xs),

            // 提示
            Text(
              isCorrect ? '筆畫準確，繼續加油！' : '與正確答案有所不同',
              style: TextStyle(fontSize: 14, color: AppColors.ink2),
            ),
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
                            painter: InkPainter(strokes: userStrokes),
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
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: AppColors.jpAccent,
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

            // 按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  onNext();
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
            ),
          ],
        ),
      ),
    );
  }
}

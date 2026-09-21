import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import 'kana_exam_page.dart';

/// 考試模式選擇頁。
///
/// 之所以要獨立一頁，不是進 [KanaExamPage] 後再切換：考試中途換題型
/// 沒有意義，而且點進手寫練習頁能看到答案就是這個考試模式要解決的
/// 問題本身——選頁要先讓使用者決定要練哪一種，再進去就是一路寫到底
/// （2026-09-21 使用者要求：50 音先練，詞彙等學完再用，兩種先各自
/// 做好）。
class KanaExamModeSelectPage extends StatelessWidget {
  const KanaExamModeSelectPage({super.key});

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
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const SizedBox(width: Gap.xs),
                    const Text('📝 手寫考試', style: AppText.title),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '不看提示、憑記憶手寫，答案先藏起來——考完才公布，沒人批閱，\n重點是逼自己真的想起筆順。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink2,
                      height: 1.5,
                    ),
                  ),
                ),
                const Spacer(),
                _ModeCard(
                  emoji: '🔊',
                  title: '50 音考試',
                  desc: '聽發音，手寫出對應的平假名',
                  accentText: 'a → あ',
                  onTap: () =>
                      context.push('/kana-exam/start', extra: ExamMode.kana),
                ),
                const SizedBox(height: Gap.md),
                _ModeCard(
                  emoji: '猫',
                  title: '詞彙考試',
                  desc: '看漢字，手寫出平假名讀音',
                  accentText: '猫 → ねこ',
                  onTap: () =>
                      context.push('/kana-exam/start', extra: ExamMode.vocab),
                ),
                const Spacer(),
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.accentText,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String desc;
  final String accentText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.card),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Gap.lg),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          border: Border.all(color: AppColors.glassEdge),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.jpAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 30)),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 13, color: AppColors.ink2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    accentText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.jpAccent,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 22, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

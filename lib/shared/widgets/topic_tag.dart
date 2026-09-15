import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../domain/models/word.dart';

/// 主題小標籤，像「食物」，或「食物、水果、顏色」這種一次屬於好幾類的字。
///
/// 沒有分類就不顯示，免得整排都是「未分類」很吵。
/// 樣式刻意做得比狀態標籤輕：只有細框沒有底色，
/// 因為類別是附加資訊，不該跟「掌握 / 待複習」搶注意力。
class TopicTag extends StatelessWidget {
  const TopicTag({super.key, required this.topics});

  final List<WordTopic> topics;

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: Text(
        topics.map((t) => t.label).join('、'),
        style: const TextStyle(fontSize: 9.5, color: AppColors.ink3),
      ),
    );
  }
}

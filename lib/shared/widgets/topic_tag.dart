import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../domain/models/word.dart';

/// 主題小標籤，像「食物」。
///
/// 未分類的不顯示，免得整排都是「未分類」很吵。
/// 樣式刻意做得比狀態標籤輕：只有細框沒有底色，
/// 因為類別是附加資訊，不該跟「掌握 / 待複習」搶注意力。
class TopicTag extends StatelessWidget {
  const TopicTag({super.key, required this.topic});

  final WordTopic topic;

  @override
  Widget build(BuildContext context) {
    if (!topic.isTagged) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: Text(
        topic.label,
        style: const TextStyle(fontSize: 9.5, color: AppColors.ink3),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// 標籤小徽章，像「食物」，或「食物、水果、顏色」這種一次貼好幾個標籤的字。
///
/// 沒有標籤就不顯示，免得整排都是空的很吵。
/// 樣式刻意做得比狀態標籤輕：只有細框沒有底色，
/// 因為標籤是附加資訊，不該跟「掌握 / 待複習」搶注意力。
class TagBadge extends StatelessWidget {
  const TagBadge({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: Text(
        tags.join('、'),
        style: const TextStyle(fontSize: 9.5, color: AppColors.ink3),
      ),
    );
  }
}

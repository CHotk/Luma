import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../domain/models/word.dart';

/// 詞義豐富度小標籤，像「多義」。
///
/// 跟 [TopicTag] 同一套樣式：未分類的不顯示，細框沒有底色，
/// 因為這也是附加資訊，不該跟「掌握 / 待複習」搶注意力。
///
/// 有義項解析筆記、又允許點的時候（[tappable]），點下去會跳到那則筆記，
/// 跟 [TrapTag] 的做法一樣：清單上不給點，只有詳情頁才給點，
/// 免得跟整列的點擊打架。
class SenseTag extends StatelessWidget {
  const SenseTag({
    super.key,
    required this.senseCount,
    this.noteNo,
    this.tappable = false,
  });

  final WordSenseCount senseCount;

  /// 對應到義項解析的第幾則筆記。沒有筆記就是 null。
  final String? noteNo;

  final bool tappable;

  @override
  Widget build(BuildContext context) {
    if (!senseCount.isTagged) return const SizedBox.shrink();

    final canOpen = tappable && noteNo != null;
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: Text(
        canOpen ? '${senseCount.label} · 看義項' : senseCount.label,
        style: const TextStyle(fontSize: 9.5, color: AppColors.ink3),
      ),
    );

    if (!canOpen) return tag;
    return GestureDetector(
      onTap: () => context.push('/notes/senses/$noteNo'),
      child: tag,
    );
  }
}

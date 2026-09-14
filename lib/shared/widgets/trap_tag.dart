import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';

/// 地雷字標記。
///
/// 意思是「這個字有陷阱，講錯會失禮或被誤會」，
/// 像 napkin 在美式英文裡有時候指衛生棉，fat 直接對人講很不禮貌。
///
/// 哪些字算地雷不是另外維護的名單，是從用法地雷那份文件的「相關單字」推出來的，
/// 所以寫了筆記就自動標上，不會忘記同步。
class TrapTag extends StatelessWidget {
  const TrapTag({super.key, required this.noteNo, this.tappable = false});

  /// 對應到第幾則筆記。
  final String noteNo;

  /// 可不可以點進去看那則筆記。清單上不給點，免得跟整列的點擊打架。
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.mid.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 11,
            color: AppColors.mid,
          ),
          const SizedBox(width: 3),
          Text(
            tappable ? '地雷字 · 看說明' : '地雷字',
            style: const TextStyle(fontSize: 9.5, color: AppColors.mid),
          ),
        ],
      ),
    );

    if (!tappable) return tag;
    return GestureDetector(
      onTap: () => context.push('/notes/$noteNo'),
      child: tag,
    );
  }
}

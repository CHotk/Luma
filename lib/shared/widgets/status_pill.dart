import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../domain/models/word.dart';

/// 狀態標籤。三種狀態的顏色只在這裡決定，其他地方不要各染各的。
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final WordStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      WordStatus.confirmed => AppColors.statusMastered,
      WordStatus.learning => AppColors.statusLearning,
      WordStatus.pending => AppColors.statusPending,
      WordStatus.untested => AppColors.statusUntested,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

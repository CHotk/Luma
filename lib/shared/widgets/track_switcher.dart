import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';

/// 語言軌道。目前只有英文有完整的學習流程，日文只有五十音手寫練習。
enum LearningTrack {
  en('英文', '/home'),
  ja('日文', '/jp-home');

  const LearningTrack(this.label, this.homeRoute);
  final String label;
  final String homeRoute;
}

/// 語言軌道切換，玻璃風格的下拉選單，英文／日文首頁共用（使用者
/// 2026-09-17 決定拿掉原本的國旗圖示，改用這個）。切換是換到另一個
/// 軌道的首頁，用 `go` 不是 `push`——這是平行的兩個首頁，不是主頁面
/// 底下的子頁面，不應該疊在返回堆疊裡，來回切換也不該越疊越深。
class TrackSwitcher extends ConsumerWidget {
  const TrackSwitcher({super.key, required this.current});

  final LearningTrack current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<LearningTrack>(
      color: const Color(0xFF1A1A24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.glassEdge),
      ),
      itemBuilder: (_) => [
        for (final track in LearningTrack.values)
          PopupMenuItem(
            value: track,
            child: Text(
              track.label,
              style: const TextStyle(color: AppColors.ink),
            ),
          ),
      ],
      onSelected: (track) {
        if (track == current) return;
        // 存起來給開機畫面看，下次啟動才不會固定跳回英文首頁
        // （2026-09-18 使用者要求，見 [SettingsRepository.saveLastTrack]）。
        ref.read(settingsRepositoryProvider).saveLastTrack(track.name);
        context.go(track.homeRoute);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16, color: AppColors.ink2),
          ],
        ),
      ),
    );
  }
}

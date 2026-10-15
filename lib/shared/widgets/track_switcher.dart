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

/// 語言軌道切換，英文／日文首頁共用：一顆膠囊切兩半，左英文、右日文，
/// 目前那邊亮起來（2026-10-15 使用者要求，取代原本的下拉選單——首頁
/// 標題的時間拿掉後有位置了）。切換是換到另一個軌道的首頁，用 `go` 不是
/// `push`——這是平行的兩個首頁，不是主頁面底下的子頁面，不應該疊在返回
/// 堆疊裡，來回切換也不該越疊越深。
class TrackSwitcher extends ConsumerWidget {
  const TrackSwitcher({super.key, required this.current});

  final LearningTrack current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void pick(LearningTrack track) {
      if (track == current) return;
      // 存起來給開機畫面看，下次啟動才不會固定跳回英文首頁
      // （2026-09-18 使用者要求，見 [SettingsRepository.saveLastTrack]）。
      ref.read(settingsRepositoryProvider).saveLastTrack(track.name);
      context.go(track.homeRoute);
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final track in LearningTrack.values)
            GestureDetector(
              onTap: () => pick(track),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: track == current
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  track.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: track == current ? AppColors.ink : AppColors.ink3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

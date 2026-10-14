import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme/colors.dart';

/// 多裝置同步跑到哪了：一共幾項、做完幾項、現在還在跑哪幾項。null＝
/// 沒在同步。由 `r2_sync_section.dart` 的 `_syncNow` 更新。
class SyncProgress {
  const SyncProgress({
    required this.total,
    required this.done,
    required this.running,
  });

  final int total;
  final int done;

  /// 還在跑的功能名稱，照開始的順序。
  final List<String> running;
}

final syncProgressProvider = StateProvider<SyncProgress?>((ref) => null);

/// 同步途中跳去別的頁面時，最上面一條即時進度（2026-10-12 使用者要求：
/// 同步中跳去其他地方，上面通知要顯示即時進度）。在多裝置同步頁本身
/// 不顯示（那頁每一項都有自己的狀態）。點一下回同步頁。跑完這條收起來，
/// 換成原本的「本裝置從雲端更新：…」通知。
///
/// 放在 `MaterialApp.router` 的 builder 裡（[SyncProgressFrame]）。
class SyncProgressBanner extends ConsumerWidget {
  const SyncProgressBanner({super.key});

  /// 現在要不要顯示：有在同步、而且不在同步頁。
  static bool visible(SyncProgress? progress) =>
      progress != null && !currentAppPath().startsWith('/sync');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(syncProgressProvider);
    return ListenableBuilder(
      listenable: appRouter.routerDelegate,
      builder: (context, _) {
        final show = visible(progress);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => SizeTransition(
            sizeFactor: anim,
            axisAlignment: -1,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: show
              ? _Bar(key: const ValueKey('bar'), progress: progress!)
              : const SizedBox.shrink(key: ValueKey('none')),
        );
      },
    );
  }
}

/// 進度條放在頁面上方、把頁面往下推，不是蓋在頁面上（2026-10-12 使用者
/// 回報：蓋住左上角選單，點進同步頁就出不去）。顯示時頁面自己的上方安全
/// 區拿掉，不然進度條跟頁面標題中間會多一段空白。
class SyncProgressFrame extends ConsumerWidget {
  const SyncProgressFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(syncProgressProvider);
    return ListenableBuilder(
      listenable: appRouter.routerDelegate,
      builder: (context, _) {
        final show = SyncProgressBanner.visible(progress);
        return ColoredBox(
          color: AppColors.bg,
          child: Column(
            children: [
              const SyncProgressBanner(),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: show,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final fraction = p.total == 0 ? 0.0 : p.done / p.total;
    final runningText = p.running.isEmpty ? '收尾中…' : '${p.running.join('、')}…';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => appRouter.push('/sync'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                      decoration: BoxDecoration(
                        color: const Color(0xE61E1E2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                '同步中 ${p.done}／${p.total}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  runningText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.ink2,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppColors.ink3,
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: fraction),
                              duration: const Duration(milliseconds: 300),
                              builder: (context, v, _) =>
                                  LinearProgressIndicator(
                                    value: v,
                                    minHeight: 4,
                                    color: AppColors.accent,
                                    backgroundColor: const Color(0xFF2A2A3D),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

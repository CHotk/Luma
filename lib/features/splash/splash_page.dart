import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/lume_mark.dart';
import '../../shared/widgets/track_switcher.dart';

/// 啟動畫面。
///
/// 停留多久才自動跳轉見 `assets/config/app_defaults.yaml` 的
/// `splashHoldMs`（唯一來源，這裡不寫死）。不要做成要使用者點一下
/// 才進去，每天都要看的東西多一次點擊就是多一分懶得開。
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNavigate();
  }

  Future<void> _scheduleNavigate() async {
    final hold = await loadSplashHoldDuration();
    // 跳去上次用的軌道，不是固定跳英文——不然常用日文軌道的人每次
    // 開 App 都要手動切一次（2026-09-18 使用者要求，見
    // [SettingsRepository.loadLastTrack]）。沒存過（全新使用者）才
    // 用預設的英文。
    final lastTrack = await ref.read(settingsRepositoryProvider).loadLastTrack();
    final route = lastTrack == LearningTrack.ja.name
        ? LearningTrack.ja.homeRoute
        : LearningTrack.en.homeRoute;
    if (!mounted) return;
    _timer = Timer(hold, () {
      if (mounted) context.go(route);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App 圖示（使用者換上的 logo，2026-09-24），讀不到就退回原本畫
              // 出來的標誌。
              Image.asset(
                'assets/images/app_logo/logo.png',
                width: 120,
                height: 120,
                errorBuilder: (context, error, stack) =>
                    const LumeMark(size: 96),
              ),
              const SizedBox(height: 14),
              const Text(
                'Lume',
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                '微 光',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4.4,
                  color: AppColors.ink2,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '一天一點未來光',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/lume_mark.dart';

/// 啟動畫面。
///
/// 停留多久才自動跳轉見 `assets/config/app_defaults.yaml` 的
/// `splashHoldMs`（唯一來源，這裡不寫死）。不要做成要使用者點一下
/// 才進去，每天都要看的東西多一次點擊就是多一分懶得開。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNavigate();
  }

  Future<void> _scheduleNavigate() async {
    final hold = await loadSplashHoldDuration();
    if (!mounted) return;
    _timer = Timer(hold, () {
      if (mounted) context.go('/home');
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
              const LumeMark(size: 96),
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

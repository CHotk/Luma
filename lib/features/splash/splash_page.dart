import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/lume_mark.dart';

/// 把 `assets/images/app_logo/<檔名>` 換成 `assets/images/app_logo/splash/
/// <檔名>`（縮小過的版本，見 tool/resize_splash_logo.dart），不是這個
/// 資料夾底下的路徑就原樣傳回——目前只有啟動畫面會用到縮小版本。
String _splashAssetFor(String assetPath) {
  const dir = 'assets/images/app_logo/';
  if (!assetPath.startsWith(dir) || assetPath.startsWith('${dir}splash/')) {
    return assetPath;
  }
  return '${dir}splash/${assetPath.substring(dir.length)}';
}

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
    // 2026-09-24：功能變多，開機改進 App 首頁（圖示格），不再直接進語言學習。
    const route = '/start';
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
              // App 圖示：使用者可以在設定頁的「App Logo」挑
              // `assets/images/app_logo/` 裡的任一張圖（2026-09-29 加），
              // 沒選過就用預設的 logo02.png（2026-09-30 使用者要求把預設
              // 從 logo.png 換成 logo02.png）；讀不到（檔案被搬走等）就
              // 退回原本畫出來的標誌。
              Image.asset(
                // 讀 `splash/` 底下縮小過的版本（見
                // tool/resize_splash_logo.dart），不是原始解析度那張
                // ——原圖是 1254x1254、1.2~1.6MB，但這裡只顯示 120x120，
                // 就算瀏覽器快取住原圖，每次 App 冷啟動引擎重新初始化
                // 還是要整張解碼一次，這個 CPU 成本每次開機都要重付
                // （2026-09-30 使用者回報「logo 每次重開都慢」的根因）。
                // 縮小版本目前只有 logo.png／logo02.png 兩張（設定頁能選
                // 的 App Logo 就這兩個選項），還沒有更多選項時直接對應
                // 檔名替換資料夾即可；讀不到就退回 [LumeMark]，不會噴例外。
                _splashAssetFor(
                  ref.watch(appLogoAssetProvider) ??
                      'assets/images/app_logo/logo02.png',
                ),
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

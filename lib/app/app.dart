import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/colors.dart';

/// 讓滑鼠也能像手機觸控一樣按住拖拉捲動。
///
/// Flutter 預設只有觸控（跟觸控筆）能拖拉捲動，滑鼠只能用滾輪或拉捲軸，
/// 網頁版用滑鼠測試/操作單字庫這種長清單會很不順手（使用者 2026-09-15 要求）。
/// 這裡是全 App 共用的設定，不是單字庫自己加，不然其他清單（筆記、總紀錄、
/// 設定頁）滑鼠拖拉會不一致，變成有的頁面能拖有的不能。
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

/// App 進入點。
///
/// 固定深色，不做淺色模式（使用者 2026-09-11 決定）。
/// 所以這裡直接寫死 dark，不去看系統設定。
class LumeApp extends StatelessWidget {
  const LumeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Lume',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      scrollBehavior: _AppScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.bg,
          primary: AppColors.accent,
          secondary: AppColors.accentSolid,
          error: AppColors.bad,
        ),
        // 之後打包思源黑體時，字體只要在這裡指定一次。
        fontFamily: null,
        useMaterial3: true,
      ),
    );
  }
}

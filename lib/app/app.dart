import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/colors.dart';

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

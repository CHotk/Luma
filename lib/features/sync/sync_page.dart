import 'package:flutter/material.dart';

import '../../app/theme/spacing.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../settings/r2_sync_section.dart';

/// 多裝置同步，獨立成一個功能頁面，不是塞在「設定」頁裡的一個區塊
/// ——2026-09-23 使用者要求：這個功能夠獨立、之後會一直擴充（日記
/// 之外的功能陸續加進來），該有自己的入口，不該埋在設定頁一堆規則
/// 選項中間。選單裡排在「除錯」正上方，跟 `debug_log_page.dart` 同一種
/// 「大功能首頁」處理方式（`showBack: false`，靠側邊選單導航進來，不
/// 是子頁面鑽進來的）。
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                const AppTopBar(title: '多裝置同步', showBack: false),
                const SizedBox(height: Gap.md),
                const Expanded(
                  child: SingleChildScrollView(child: R2SyncSection()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

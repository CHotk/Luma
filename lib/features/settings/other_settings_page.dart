import 'package:flutter/material.dart';

import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';

/// 英文學習以外的功能（日記、健身、YT、日文…）點齒輪來到的設定頁。
/// 這些功能還沒有自己的設定項目，先留白，之後有了再各自填內容。
class OtherSettingsPage extends StatelessWidget {
  const OtherSettingsPage({super.key});

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
                const AppTopBar(title: '設定', showSettings: false),
                Expanded(
                  child: Center(
                    child: Text('這個功能還沒有設定項目', style: AppText.bodyDim),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

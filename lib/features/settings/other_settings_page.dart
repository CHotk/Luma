import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../yt_tracker/yt_api_key_dialog.dart';
import '../yt_tracker/yt_tracker_home_page.dart' show showYtExportDialog;

/// 英文學習以外的功能（日記、健身、YT、日文…）點齒輪來到的設定頁。
/// [fromLocation] 是點齒輪那一刻所在的路徑（見 `open_settings.dart`），
/// 用來決定要顯示哪個功能專屬的設定項目——目前只有 YT 頻道追蹤有
/// （API 金鑰、匯出分類／頻道，2026-09-29 使用者要求從頂部列的按鈕
/// 移進齒輪，原本那排按鈕太擠），其他功能還沒有設定項目就照舊留白。
class OtherSettingsPage extends ConsumerWidget {
  const OtherSettingsPage({super.key, this.fromLocation});

  final String? fromLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isYtTracker = fromLocation?.startsWith('/yt-tracker') ?? false;
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
                const SizedBox(height: Gap.md),
                Expanded(
                  child: isYtTracker
                      ? const _YtTrackerSettings()
                      : Center(
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

class _YtTrackerSettings extends ConsumerWidget {
  const _YtTrackerSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = (ref.watch(ytApiKeyProvider) ?? '').isNotEmpty;
    return ListView(
      children: [
        Text('YT 頻道追蹤', style: AppText.note),
        const SizedBox(height: Gap.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasKey ? Icons.vpn_key : Icons.vpn_key_outlined,
                    size: 18,
                    color: hasKey ? AppColors.ok : AppColors.ink2,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YouTube API 金鑰',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(hasKey ? '已儲存' : '還沒設定', style: AppText.note),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => showYtApiKeyDialog(context, ref),
                    child: const Text('設定'),
                  ),
                ],
              ),
              const Divider(height: Gap.lg, color: AppColors.glassEdge),
              Row(
                children: [
                  const Icon(
                    Icons.ios_share_rounded,
                    size: 18,
                    color: AppColors.ink2,
                  ),
                  const SizedBox(width: Gap.sm),
                  const Expanded(
                    child: Text(
                      '匯出分類／頻道',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showYtExportDialog(context, ref),
                    child: const Text('匯出'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

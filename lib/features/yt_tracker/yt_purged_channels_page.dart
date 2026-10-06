import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'yt_channel_avatar.dart';
import 'yt_video_row.dart' show openExternalUrl;

/// 永久刪除的頻道清單（2026-10-06 使用者要求：放在 YT 設定裡，想看自己
/// 刪了哪些可以點開）。每一列：頭像、名稱、訂閱人數、什麼時候永久刪除；
/// 點一下開那個頻道的 YouTube 頁面。
///
/// 不給還原鈕（使用者：「都確定刪除了」），但資料是整筆留著的（見
/// [YtChannel.purgedAt]），之後想加還原只要呼叫
/// [YtTrackerRepository.restoreChannel]，不會有資料遺失。
class YtPurgedChannelsPage extends ConsumerWidget {
  const YtPurgedChannelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const AppTopBar(
                  title: '永久刪除的頻道',
                  titleIcon: Icons.delete_forever_outlined,
                  titleIconColor: AppColors.ytAccent,
                  showSettings: false,
                ),
                const SizedBox(height: Gap.md),
                Expanded(
                  child: FutureBuilder<List<YtChannel>>(
                    future: ref
                        .read(ytTrackerRepositoryProvider)
                        .loadPurgedChannels(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final channels = snap.data!;
                      if (channels.isEmpty) {
                        return const SingleChildScrollView(
                          child: InlineEmptyCard(
                            title: '沒有永久刪除的頻道',
                            message: '在垃圾桶裡長按頻道選「永久刪除」，就會出現在這裡',
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: channels.length + 1,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: AppColors.glassEdge,
                        ),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Gap.sm),
                              child: Text(
                                '共 ${channels.length} 個・點一下開 YouTube 頻道頁',
                                style: AppText.note,
                              ),
                            );
                          }
                          return _PurgedRow(channel: channels[i - 1]);
                        },
                      );
                    },
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

class _PurgedRow extends StatelessWidget {
  const _PurgedRow({required this.channel});

  final YtChannel channel;

  /// 頻道網址：有存使用者貼的網址就用它，沒有就用頻道 ID 組。
  String? get _url {
    if (channel.url.trim().isNotEmpty) return channel.url.trim();
    if (channel.youtubeChannelId.isNotEmpty) {
      return 'https://www.youtube.com/channel/${channel.youtubeChannelId}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final at = channel.purgedAt!;
    final url = _url;
    return InkWell(
      onTap: url == null ? null : () => openExternalUrl(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            YtChannelAvatar(channel: channel, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${at.year}/${at.month}/${at.day} 永久刪除',
                      if (channel.subscriberLabel != null)
                        channel.subscriberLabel!,
                    ].join('・'),
                    style: AppText.note,
                  ),
                ],
              ),
            ),
            if (url != null)
              const Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: AppColors.ink3,
              ),
          ],
        ),
      ),
    );
  }
}

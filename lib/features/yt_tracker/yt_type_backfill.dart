import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../data/services/yt_video_type_scanner.dart';
import '../../shared/widgets/app_notice.dart';

/// 一次把所有頻道快取裡的影片補上類型（一般影片／Shorts／直播）。
/// 2026-10-05 使用者要求：先一次補齊目前快取有的全部影片，之後就只要
/// 打開頻道時背景補新影片（見 [YtVideoTypeScanner]）。每個頻道只翻到
/// 它快取裡最舊那部為止，掃到哪會記下來，所以中途配額用完或關掉，
/// 再按一次會接著做，不會重翻已經掃過的。
Future<void> runYtTypeBackfill(BuildContext context, WidgetRef ref) async {
  final apiKey = ref.read(ytApiKeyProvider);
  if (apiKey == null || apiKey.isEmpty) {
    showAppNotice(context, '還沒設定 API 金鑰，無法補類型', isError: true);
    return;
  }
  final channels = await ref.read(ytTrackerRepositoryProvider).loadChannels();
  if (!context.mounted) return;
  final status = ValueNotifier<String>('準備中…');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, text, _) => Text(text, style: AppText.body),
            ),
          ),
        ],
      ),
    ),
  );

  final kv = ref.read(keyValueStoreProvider);
  final cache = YtVideoCacheStore(kv);
  final scanner = YtVideoTypeScanner(YoutubeApiService(apiKey), kv);
  var tagged = 0;
  var scanned = 0;
  String? error;
  for (var i = 0; i < channels.length; i++) {
    final c = channels[i];
    status.value = '補類型中 ${i + 1}/${channels.length}\n${c.name}';
    var uploadsId = c.uploadsPlaylistId;
    if (uploadsId.isEmpty && c.youtubeChannelId.startsWith('UC')) {
      uploadsId = 'UU${c.youtubeChannelId.substring(2)}';
    }
    if (uploadsId.isEmpty || (await cache.load(c.id)).isEmpty) continue;
    try {
      tagged += await scanner.scan(channelId: c.id, uploadsId: uploadsId);
      scanned++;
    } catch (e) {
      // 多半是配額用完：停下來，進度已經存了，明天再按會接著做。
      error = '$e';
      break;
    }
  }
  status.dispose();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (error != null) {
    showAppNotice(
      context,
      '補到一半停下來了（$error）。已完成 $scanned 個頻道，之後再按會接著做',
      isError: true,
    );
  } else {
    showAppNotice(context, '補好了：$scanned 個頻道、$tagged 部影片更新了類型');
  }
}

/// YT 設定頁上的那一列。
class YtTypeBackfillRow extends ConsumerWidget {
  const YtTypeBackfillRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Icon(Icons.category_outlined, size: 18, color: AppColors.ink2),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '補齊影片類型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text('把快取裡所有影片標上一般／Shorts／直播', style: AppText.note),
            ],
          ),
        ),
        TextButton(
          onPressed: () => runYtTypeBackfill(context, ref),
          child: const Text('開始'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/services/youtube_api_service.dart';

/// 開外部連結，失敗就退回複製到剪貼簿——跟匯出檔案失敗退回複製剪貼簿
/// 同一個處理哲學。之前直接呼叫 `launchUrl(..., mode:
/// LaunchMode.externalApplication)` 沒包 try/catch，網頁上丟出例外會
/// 整個吃掉沒有任何畫面回饋，使用者只會覺得「點了沒反應」（2026-09-22
/// 使用者回報主控台真的有 Uncaught Error）。`externalApplication` 這個
/// mode 本來是手機平台用來指定「真的開瀏覽器 App 不要用內嵌 WebView」，
/// 網頁版沒有這個區分，改用 `platformDefault` 比較安全。
Future<void> openExternalUrl(BuildContext context, String url) async {
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('打不開連結，已複製到剪貼簿，貼到瀏覽器網址列開')),
  );
}

/// 影片列的通用元件：縮圖＋標題＋副標（頻道名稱和/或發布時間），點下去
/// 開新分頁到真正的 YouTube 影片。「依影片顯示」（混合多頻道）跟頻道
/// 詳情頁（單一頻道）共用同一顆，不要各刻一份（2026-09-22 使用者回報：
/// 頻道詳情頁忘記接真的影片資料，順便把畫面也共用掉，以後兩邊行為才會
/// 一直一致，不會改一邊漏改另一邊）。
class YtVideoRow extends StatelessWidget {
  const YtVideoRow({super.key, required this.video, required this.subtitle});

  final YoutubeVideo video;

  /// 「依影片顯示」混合多頻道，要秀「頻道名稱・幾天前」；頻道詳情頁
  /// 已經知道是哪個頻道了，只傳「幾天前」就好。
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openExternalUrl(context, video.watchUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    video.thumbnailUrl,
                    width: 96,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                      width: 96,
                      height: 54,
                      color: AppColors.glassFill,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        size: 16,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                ),
                // 右下角時長角標，跟 YouTube 網站同一種慣例位置——API
                // 沒辦法在抓清單那支就給，要多打一次 videos.list 才有
                // （見 youtube_api_service.dart 的 fetchDurations），
                // 還沒抓到就先不顯示，不要顯示假的 0:00。
                if (video.duration != null)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatVideoDuration(video.duration!),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppText.note),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String ytRelativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} 個月前';
  return '${(diff.inDays / 365).floor()} 年前';
}

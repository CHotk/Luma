import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/external_link.dart';
import '../../data/services/youtube_api_service.dart';

/// 開外部連結，失敗就退回複製到剪貼簿——跟匯出檔案失敗退回複製剪貼簿
/// 同一個處理哲學。
///
/// 這裡**不能**用 `url_launcher`：它在網頁版走 plugin channel，`launch`
/// 呼叫到真正執行 `window.open` 中間一定會夾至少一個 await／microtask。
/// 桌機瀏覽器對「這次 window.open 算不算使用者手勢觸發」判斷比較寬鬆，
/// 夾一個 microtask 還是會放行；手機 Safari 判斷嚴格很多，只要不是在
/// 點擊事件處理常式裡「同步」呼叫就直接擋掉，使用者只會看到打不開
/// （2026-09-23 使用者拿實機回報才抓到，桌機版之前修的是另一個問題：
/// 未捕捉例外，不是這個彈窗封鎖）。改用 [openExternalUrlSync] 同步直接
/// 呼叫 `window.open`，就在點擊當下那個呼叫堆疊裡執行，不夾任何 await。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final opened = openExternalUrlSync(url);
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

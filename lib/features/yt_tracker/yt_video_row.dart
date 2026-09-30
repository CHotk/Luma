import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/external_link.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_video_watch.dart';
import '../../shared/widgets/app_notice.dart';

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
  showAppNotice(context, '打不開連結，已複製到剪貼簿，貼到瀏覽器網址列開', isError: true);
}

/// 影片列的通用元件：縮圖＋標題＋副標（頻道名稱和/或發布時間），點下去
/// 開新分頁到真正的 YouTube 影片。「依影片顯示」（混合多頻道）跟頻道
/// 詳情頁（單一頻道）共用同一顆，不要各刻一份（2026-09-22 使用者回報：
/// 頻道詳情頁忘記接真的影片資料，順便把畫面也共用掉，以後兩邊行為才會
/// 一直一致，不會改一邊漏改另一邊）。
///
/// 「點開過」的標記也集中在這裡處理（2026-09-29 使用者要求：不管從
/// 哪裡、用什麼方式點開影片都要標記成看過、記時間戳）——所有點影片的
/// 路徑本來就都會經過這顆共用元件的 `onTap`，標記邏輯放這裡一次涵蓋
/// 全部呼叫端，不用每個列表頁自己接一份。
class YtVideoRow extends ConsumerStatefulWidget {
  const YtVideoRow({super.key, required this.video, required this.subtitle});

  final YoutubeVideo video;

  /// 「依影片顯示」混合多頻道，要秀「頻道名稱・幾天前」；頻道詳情頁
  /// 已經知道是哪個頻道了，只傳「幾天前」就好。
  final String subtitle;

  @override
  ConsumerState<YtVideoRow> createState() => _YtVideoRowState();
}

class _YtVideoRowState extends ConsumerState<YtVideoRow> {
  YtVideoWatchRecord? _watched;

  @override
  void initState() {
    super.initState();
    _loadWatched();
  }

  Future<void> _loadWatched() async {
    final record = await YtVideoWatchStore(
      ref.read(keyValueStoreProvider),
    ).get(widget.video.videoId);
    if (mounted && record != null) setState(() => _watched = record);
  }

  Future<void> _open() async {
    // 開連結一定要是這個函式最先做的事，中間不能先 await 別的東西
    // ——`openExternalUrl` 內部第一步是同步呼叫 `window.open`，手機瀏覽器
    // 只認「使用者手勢觸發後、還沒夾過 await」的呼叫堆疊，先 await 標記
    // 已看過的存檔動作會把這個呼叫堆疊斷開，導致點了打不開
    // （2026-09-30 使用者回報：加了已看過標記之後點影片就跳不出去了，
    // 就是這裡的順序錯了，跟 `external_link.dart` 的說明是同一個坑）。
    await openExternalUrl(context, widget.video.watchUrl);
    final record = await YtVideoWatchStore(
      ref.read(keyValueStoreProvider),
    ).markOpened(widget.video.videoId);
    if (mounted) setState(() => _watched = record);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return InkWell(
      onTap: _open,
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
                // 左上角「已看過」小標籤，滑鼠停留／長按顯示第一次、最近
                // 一次點開的時間跟總共看過幾次（2026-09-29 使用者要求：
                // 要有小提示或小標籤，且每一次點開都要記時間戳，不是只記
                // 第一次跟最近一次）。
                if (_watched != null)
                  Positioned(
                    left: 3,
                    top: 3,
                    child: Tooltip(
                      message:
                          '已看過・${ytRelativeTime(_watched!.firstWatchedAt)}\n'
                          '最近一次：${ytRelativeTime(_watched!.lastOpenedAt)}'
                          '${_watched!.openedAt.length > 1 ? '\n共看過 ${_watched!.openedAt.length} 次' : ''}',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.ytAccent.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.visibility_rounded,
                          size: 10,
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
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _watched != null ? AppColors.ink3 : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.subtitle, style: AppText.note),
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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/external_link.dart';
import '../../data/repositories/yt_embed_player_style_store.dart';
import '../../data/repositories/yt_video_hidden_store.dart';
import '../../data/repositories/yt_video_open_mode_store.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_video_watch.dart';
import '../../shared/widgets/app_notice.dart';
import 'yt_embedded_player.dart';
import 'yt_floating_player.dart';

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

/// 內嵌播放器共通的三種外層呈現方式之一：最早的版本，正中央的 [Dialog]，
/// 整頁變暗蓋住底下內容（2026-09-30 使用者要求：後來雖然改做了下滑
/// 收合式、浮動視窗，這個舊版本還是留著讓使用者能在設定頁切回來，不是
/// 做新的就把舊的拿掉）。右上角留一顆「在 YouTube 開啟」的理由、跟
/// [buildYtEmbeddedPlayer] 的關係，見 [showYtEmbeddedBottomSheet] 的
/// 說明，三個呈現方式都一樣。
Future<void> showYtEmbeddedCenteredDialog(
  BuildContext context, {
  required String videoId,
  required String title,
  required String watchUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: const Color(0xFF1A1A24),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => openExternalUrl(dialogContext, watchUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    color: AppColors.ink2,
                    tooltip: '在 YouTube 開啟',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.ink2,
                    tooltip: '關閉',
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: buildYtEmbeddedPlayer(videoId),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 內嵌播放器（2026-09-30 使用者要求：點影片開新分頁那一刻感覺像離開了
/// App，希望能不用離開直接在裡面看）。右上角留一顆「在 YouTube 開啟」
/// ——使用者原話「反正內嵌的 點一下 也能去yt」：內嵌播放器功能陽春
/// （不能按讚、留言、開彈幕），不能把人鎖死在裡面，想要完整功能隨時能
/// 一鍵跳去真正的 YouTube。
///
/// 外層容器原本是置中的 [Dialog]（整頁變暗＋正中央一個方框，還留著見
/// [showYtEmbeddedCenteredDialog]），使用者回饋不喜歡這種「整頁被蓋住」
/// 的感覺，2026-09-30 改成從下方滑出的 [showModalBottomSheet]——背後
/// 列表看得到（半透明遮罩，不是全黑）、只佔下半螢幕、往下滑或點旁邊
/// 空白處收合，手機上比較接近一般 App 常見的影片彈出模式。**注意**：
/// 換的只是外層容器，裡面 [buildYtEmbeddedPlayer] 那個 iframe 本身
/// （autoplay/mute 參數、picture-in-picture 授權）完全不受影響，關閉時
/// 一樣整個從畫面上移除、底層 iframe 節點跟著銷毀，不會背景偷跑。
Future<void> showYtEmbeddedBottomSheet(
  BuildContext context, {
  required String videoId,
  required String title,
  required String watchUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A24),
    barrierColor: Colors.black.withValues(alpha: 0.5),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖曳把手，提示「往下滑可以收合」（2026-09-30 改滑出式時加）。
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 2),
            child: SizedBox(
              width: 36,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.glassEdge,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => openExternalUrl(sheetContext, watchUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  color: AppColors.ink2,
                  tooltip: '在 YouTube 開啟',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.ink2,
                  tooltip: '關閉',
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: buildYtEmbeddedPlayer(videoId),
          ),
        ],
      ),
    ),
  );
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
///
/// 往左滑會露出兩顆動作鈕：「開啟紀錄」看這支影片每一次被點開的時間戳
/// （2026-09-30 使用者要求：小標籤的 tooltip 手機上長按才看得到、也只
/// 顯示最新最舊兩筆，要有個地方能好好看完整紀錄）、「隱藏」把這支影片
/// 從列表裡收掉（不是刪除，影片本身是即時打 API 抓的，沒有「刪除」這
/// 回事，純粹是這台裝置「不想再看到它」的個人標記，見
/// `yt_video_hidden_store.dart`）。隱藏狀態也是這顆元件自己內部管理，
/// 跟「看過了嗎」同一套自包含做法——下次這支影片又被抓進列表裡，
/// `initState` 會重新讀到隱藏狀態，直接渲染成空的，不用列表頁那邊
/// 額外過濾。
class YtVideoRow extends ConsumerStatefulWidget {
  const YtVideoRow({
    super.key,
    required this.video,
    required this.subtitle,
    this.forceShow = false,
    this.onHiddenChanged,
    this.fromCache = false,
  });

  final YoutubeVideo video;

  /// 這支影片這次是從本機快取讀到的，不是真的打 API 抓來的（2026-09-30
  /// 使用者要求：想知道畫面上哪些是「秒出來、不用配額」的）。純粹視覺
  /// 標記，不影響任何行為；只有 `yt_tracker_channel_page.dart` 的「全部
  /// 影片」清單會傳這個（那邊往下滑載入更多會先查本機快取，見
  /// `_loadMoreVideos` 的說明），其他呼叫端不用管，預設 false 不會顯示。
  final bool fromCache;

  /// 「依影片顯示」混合多頻道，要秀「頻道名稱・幾天前」；頻道詳情頁
  /// 已經知道是哪個頻道了，只傳「幾天前」就好。
  final String subtitle;

  /// true 的話就算這支影片被隱藏過，也不會自己收成一條空白列
  /// （2026-09-30 使用者要求：頻道詳情頁要有「顯示已隱藏的影片」的
  /// 開關，開了就是要看那些被隱藏的，不能被這顆元件自己擋掉）。這種
  /// 情況下滑開的動作鈕會換成「取消隱藏」而不是「隱藏」。
  final bool forceShow;

  /// 這支影片的隱藏狀態被使用者自己改動（隱藏／取消隱藏）之後呼叫一聲
  /// ——列表頁如果自己也快取了一份隱藏清單（拿來決定要不要把這支影片
  /// 算進清單），可以藉此知道要重新整理，不給就不通知，呼叫端自己
  /// 決定要不要接。
  final VoidCallback? onHiddenChanged;

  @override
  ConsumerState<YtVideoRow> createState() => _YtVideoRowState();
}

class _YtVideoRowState extends ConsumerState<YtVideoRow> {
  /// 往左滑露出的動作區寬度（兩顆鈕＋間距）。
  static const _actionsWidth = 156.0;

  /// 拉過頭時還能再多拉多少（橡皮筋，iOS 原生的手感），放手就彈回。
  static const _overscroll = 36.0;

  YtVideoWatchRecord? _watched;
  bool _hidden = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadWatched();
    _loadHidden();
  }

  Future<void> _loadWatched() async {
    final record = await YtVideoWatchStore(
      ref.read(keyValueStoreProvider),
    ).get(widget.video.videoId);
    if (mounted && record != null) setState(() => _watched = record);
  }

  Future<void> _loadHidden() async {
    final hidden = await YtVideoHiddenStore(
      ref.read(keyValueStoreProvider),
    ).contains(widget.video.videoId);
    if (mounted && hidden) setState(() => _hidden = true);
  }

  Future<void> _open() async {
    if (ref.read(ytVideoOpenModeProvider) == YtVideoOpenMode.embedded) {
      // 內嵌播放是彈出 App 自己的對話框，不是叫瀏覽器開新分頁，沒有
      // window.open 那個「必須同步呼叫」的顧慮，可以先標記已看過再開。
      final record = await YtVideoWatchStore(
        ref.read(keyValueStoreProvider),
      ).markOpened(widget.video.videoId);
      if (mounted) setState(() => _watched = record);
      if (!context.mounted) return;
      // 呈現方式設定頁能切（2026-09-30 使用者要求：正中央 Dialog、下滑
      // 收合式、可拖曳浮動視窗三種都留著，不是做了新的就把舊的換掉，
      // 預設是最新的浮動視窗）——只有浮動視窗不會擋住背後畫面，開出來
      // 就直接回傳不用等它關掉；另外兩個都是會擋互動的 modal，維持原本
      // await 到關閉才算這次點擊結束。
      switch (ref.read(ytEmbedPlayerStyleProvider)) {
        case YtEmbedPlayerStyle.floating:
          YtFloatingPlayer.show(
            context,
            videoId: widget.video.videoId,
            title: widget.video.title,
            watchUrl: widget.video.watchUrl,
          );
        case YtEmbedPlayerStyle.bottomSheet:
          await showYtEmbeddedBottomSheet(
            context,
            videoId: widget.video.videoId,
            title: widget.video.title,
            watchUrl: widget.video.watchUrl,
          );
        case YtEmbedPlayerStyle.centeredDialog:
          await showYtEmbeddedCenteredDialog(
            context,
            videoId: widget.video.videoId,
            title: widget.video.title,
            watchUrl: widget.video.watchUrl,
          );
      }
      return;
    }
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

  // 滑動手感（2026-10-05 使用者回報：判斷太嚴格，要很大力或滑很遠才
  // 會露出右邊的按鈕）。原本要拖過一半（74px）才打開、甩一下不算，
  // 現在：
  // - 拖超過 [_openFraction]（約 37px）就打開；從打開狀態往右拖超過
  //   同樣距離就收起來。
  // - 輕甩也算：往左甩超過 [_flingVelocity] 直接打開，往右甩直接收起，
  //   不管拖了多遠。
  // - 放手後用動畫滑到定位（[_dragging] 為 false 時才有動畫），不是
  //   瞬間跳過去。
  static const _openFraction = 0.25;
  static const _flingVelocity = 250.0;
  bool _dragging = false;
  bool _openAtDragStart = false;

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _openAtDragStart = _dragOffset <= -_actionsWidth / 2;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      // 超過動作區之後越拉越緊（只跟到手指位移的三成），跟 iOS 一樣。
      final delta = _dragOffset < -_actionsWidth && details.delta.dx < 0
          ? details.delta.dx * 0.3
          : details.delta.dx;
      _dragOffset = (_dragOffset + delta).clamp(
        -_actionsWidth - _overscroll,
        0,
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    final wasOpen = _openAtDragStart;
    final bool open;
    if (v < -_flingVelocity) {
      open = true;
    } else if (v > _flingVelocity) {
      open = false;
    } else if (wasOpen) {
      // 原本是開的：往右拉回超過一小段就收。
      open = _dragOffset < -_actionsWidth * (1 - _openFraction);
    } else {
      open = _dragOffset < -_actionsWidth * _openFraction;
    }
    setState(() {
      _dragging = false;
      _dragOffset = open ? -_actionsWidth : 0;
    });
  }

  void _closeSwipe() {
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  Future<void> _hide() async {
    await YtVideoHiddenStore(
      ref.read(keyValueStoreProvider),
    ).hide(widget.video.videoId);
    if (!mounted) return;
    setState(() => _hidden = true);
    widget.onHiddenChanged?.call();
  }

  Future<void> _unhide() async {
    await YtVideoHiddenStore(
      ref.read(keyValueStoreProvider),
    ).unhide(widget.video.videoId);
    if (!mounted) return;
    setState(() {
      _hidden = false;
      _dragOffset = 0;
    });
    widget.onHiddenChanged?.call();
  }

  /// 這支影片每一次被點開的時間戳，新到舊列出來（2026-09-30 使用者
  /// 要求：小標籤只看得到最早跟最近一次，要有個地方能看完整紀錄）。
  Future<void> _showHistory() async {
    _closeSwipe();
    final watched = _watched;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('開啟紀錄', style: TextStyle(color: AppColors.ink)),
        content: watched == null
            ? Text('這支影片還沒有開啟紀錄', style: AppText.bodyDim)
            : SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '共開啟過 ${watched.openedAt.length} 次',
                      style: AppText.bodyDim,
                    ),
                    const SizedBox(height: Gap.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 最多列 50 筆，太長的清單一樣要設上限
                            // （跟日文／英文首頁月曆卡片同一個道理）。
                            for (final t in watched.openedAt.reversed.take(50))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Text(
                                  '${t.year}/${t.month}/${t.day} '
                                  '${t.hour.toString().padLeft(2, '0')}:'
                                  '${t.minute.toString().padLeft(2, '0')}'
                                  '・${ytRelativeTime(t)}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            if (watched.openedAt.length > 50)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '還有 ${watched.openedAt.length - 50} 筆沒列出來',
                                  style: AppText.note,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden && !widget.forceShow) return const SizedBox.shrink();
    final video = widget.video;
    return ClipRect(
      child: Stack(
        children: [
          // 底層：滑開才看得到的兩顆動作鈕，貼右邊。已經被隱藏、只是靠
          // [widget.forceShow] 硬顯示出來的話，第二顆鈕換成「取消隱藏」
          // （2026-09-30 使用者要求：頻道詳情頁要能看隱藏過的影片，也要
          // 能反悔）。
          //
          // 樣子照 iOS 原生／LINE 最新 iOS 版往左滑（2026-10-06 使用者
          // 要求，原本整塊方形色塊太醜）：圓角色塊、彼此留間距、用 iOS
          // 系統色，跟著滑動距離一起長出來，圖示跟字隨寬度淡入。
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: -_dragOffset,
              padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
              child: Row(
                children: [
                  _SwipeActionButton(
                    icon: Icons.history_rounded,
                    label: '紀錄',
                    color: _iosBlue,
                    onTap: _showHistory,
                  ),
                  _hidden
                      ? _SwipeActionButton(
                          icon: Icons.visibility_rounded,
                          label: '取消隱藏',
                          color: _iosGreen,
                          onTap: _unhide,
                        )
                      : _SwipeActionButton(
                          icon: Icons.visibility_off_rounded,
                          label: '隱藏',
                          color: _iosGray,
                          onTap: _hide,
                        ),
                ],
              ),
            ),
          ),
          // 上層：原本整排內容，左右拖曳滑開／收合，不透明背景蓋住底下
          // 的動作鈕，蓋不住就會變成兩層文字疊在一起。
          // 用 RawGestureDetector 自己設橫向拖曳的起動距離：預設要先橫移
          // 18px 才算「橫向滑」，稍微斜一點的滑動常常被外層清單的直向
          // 捲動搶走，就變成「要很用力才滑得開」（2026-10-05 使用者回報）。
          // 調成 8px，橫向意圖一出現就接手。
          RawGestureDetector(
            gestures: {
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(
                    () => HorizontalDragGestureRecognizer()
                      ..gestureSettings = const DeviceGestureSettings(
                        touchSlop: 8,
                      )
                      // 從手指按下的那一點開始算位移，起動前那 8px 也算進
                      // 去，卡片才會完全跟著手指，不會少一截。
                      ..dragStartBehavior = DragStartBehavior.down,
                    (r) => r
                      ..onStart = _onDragStart
                      ..onUpdate = _onDragUpdate
                      ..onEnd = _onDragEnd,
                  ),
            },
            child: AnimatedContainer(
              // 拖曳中跟著手指走（不加動畫），放手後滑到定位。
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
              child: ColoredBox(
                color: AppColors.bg,
                child: Opacity(
                  // 靠 forceShow 硬顯示出來的隱藏影片，整排淡一點，一眼
                  // 看得出跟正常影片不一樣（2026-09-30 使用者要求的
                  // 「顯示已隱藏」情境）。
                  opacity: _hidden && widget.forceShow ? 0.5 : 1,
                  child: InkWell(
                    onTap: _dragOffset == 0 ? _open : _closeSwipe,
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
                                  // 照顯示大小解碼：YouTube 給的縮圖最大到
                                  // 480×360，原尺寸解碼每張都很佔記憶體，清單
                                  // 一長手機就吃緊（2026-10-06 效能檢查）。
                                  cacheWidth:
                                      (96 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round(),
                                  errorBuilder: (context, error, stack) =>
                                      Container(
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
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
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
                              // 左下角類型小標籤：影片／Shorts／直播
                              // （2026-10-06 使用者要求）。類型還不知道
                              // （快取裡還沒標過）就不顯示，不亂猜。
                              if (_typeLabel(video) case final label?)
                                Positioned(
                                  left: 3,
                                  bottom: 3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: label.color.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      label.text,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              // 左上角「已看過」小標籤，點下去直接開「開啟
                              // 紀錄」視窗，不是靠 Tooltip 長按才看得到
                              // （2026-09-30 使用者要求：長按太不直覺，
                              // 點一下就該看到；順便把標籤做大一點，原本
                              // 太小了）。
                              if (_watched != null)
                                Positioned(
                                  left: 3,
                                  top: 3,
                                  child: GestureDetector(
                                    onTap: _showHistory,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.ytAccent.withValues(
                                          alpha: 0.92,
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Icon(
                                        Icons.visibility_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              // 「這支是從本機快取讀的」小圓點，右上角
                              // （2026-09-30 使用者要求：想知道哪些是秒
                              // 出來、不用配額的）。純裝飾，不能點。
                              if (widget.fromCache)
                                Positioned(
                                  right: 3,
                                  top: 3,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppColors.ink2,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.black.withValues(
                                          alpha: 0.5,
                                        ),
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
                                    color: _watched != null
                                        ? AppColors.ink3
                                        : AppColors.ink,
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
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// iOS 深色模式的系統色（systemBlue／systemGray／systemGreen）。
const _iosBlue = Color(0xFF0A84FF);
const _iosGray = Color(0xFF636366);
const _iosGreen = Color(0xFF30D158);

/// 滑開影片列露出的其中一顆動作鈕：iOS 風格的圓角色塊，左邊留 6px
/// 間距。寬度由外層跟著滑動距離分配，太窄時圖示跟字先淡出、不擠成一團。
class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: LayoutBuilder(
          builder: (context, box) {
            // 寬度 24 以下完全看不到內容，到 56 才完全顯示。
            final reveal = ((box.maxWidth - 24) / 32).clamp(0.0, 1.0);
            return Material(
              color: color,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                highlightColor: Colors.black12,
                splashColor: Colors.transparent,
                child: Opacity(
                  opacity: reveal,
                  child: Transform.scale(
                    scale: 0.8 + 0.2 * reveal,
                    child: OverflowBox(
                      maxWidth: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 21, color: Colors.white),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.1,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
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

/// 影片列縮圖左下角的類型標籤：直播優先（直播也可能是直的），再來
/// Shorts，兩個都確定不是才標「影片」；還沒標過類型就是 null，不顯示。
({String text, Color color})? _typeLabel(YoutubeVideo v) {
  if (v.isLive == true) return (text: '直播', color: const Color(0xFFE53935));
  if (v.isShort == true) {
    return (text: 'Shorts', color: const Color(0xFFFF2D6F));
  }
  if (v.isShort == false && v.isLive == false) {
    return (text: '影片', color: const Color(0xFF3D5AFE));
  }
  return null;
}

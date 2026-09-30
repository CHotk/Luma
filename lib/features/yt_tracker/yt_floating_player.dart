import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import 'yt_embedded_player.dart';
import 'yt_video_row.dart' show openExternalUrl;

/// 可拖曳、可收合成邊角小泡泡的浮動播放器（2026-09-30 使用者要求：跟
/// 下滑收合式並存，設定頁可以切換，見 [YtEmbedPlayerStyle]）。
///
/// 用 [Overlay] 插進畫面，不是 [showDialog]／[showModalBottomSheet]——
/// 那兩個都會在底下墊一層 barrier 擋掉背後內容的觸控，沒辦法「一邊拖著
/// 看、一邊繼續滑列表」；Overlay 蓋在最上層但只有面板本身那塊區域會
/// 接住觸控，其餘地方直接穿透到底下，這是能做到「浮動」的關鍵。
///
/// 一次只允許存在一個浮動播放器（開新的之前自動關掉舊的），理由跟
/// `yt_embedded_player_web.dart` 的 `_registered` 集合一樣：沒有清楚的
/// 「只能有一個」規則的話，使用者連續點好幾支影片，背景會疊出一堆浮動
/// 視窗、一堆 iframe 同時在播，互搶音訊。
class YtFloatingPlayer {
  YtFloatingPlayer._();

  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String videoId,
    required String title,
    required String watchUrl,
  }) {
    close();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FloatingPlayerPanel(
        videoId: videoId,
        title: title,
        watchUrl: watchUrl,
        onClose: () {
          entry.remove();
          if (identical(_entry, entry)) _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// 關閉目前浮動中的播放器（如果有的話）。切換設定頁的呈現方式、或
  /// 要換開別支影片時呼叫，不留著背景繼續播。
  static void close() {
    _entry?.remove();
    _entry = null;
  }
}

class _FloatingPlayerPanel extends StatefulWidget {
  const _FloatingPlayerPanel({
    required this.videoId,
    required this.title,
    required this.watchUrl,
    required this.onClose,
  });

  final String videoId;
  final String title;
  final String watchUrl;
  final VoidCallback onClose;

  @override
  State<_FloatingPlayerPanel> createState() => _FloatingPlayerPanelState();
}

class _FloatingPlayerPanelState extends State<_FloatingPlayerPanel> {
  static const _panelWidth = 300.0;
  static const _panelVideoHeight = _panelWidth * 9 / 16;
  static const _headerHeight = 34.0;
  static const _panelHeight = _panelVideoHeight + _headerHeight;
  static const _bubbleSize = 56.0;

  /// 面板／泡泡共用同一個左上角位置：收合只是換一種畫法，不是換一個
  /// 元件，位置感覺上才會是「原地縮小」而不是跳來跳去。第一次 build
  /// 才算初始位置（畫面右下角，留一點安全距離），之後使用者拖過就用
  /// 他拖到的位置，不會每次重繪都跳回預設角落。
  Offset? _position;
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final size = _collapsed
        ? const Size(_bubbleSize, _bubbleSize)
        : const Size(_panelWidth, _panelHeight);
    _position = _clamp(
      _position ??
          Offset(
            screen.width - size.width - 16,
            screen.height - size.height - 96,
          ),
      screen,
      size,
    );

    return Positioned(
      left: _position!.dx,
      top: _position!.dy,
      // 影片本身（buildYtEmbeddedPlayer）從頭到尾只掛載這一次、留在
      // 樹裡不拔掉——收合時用 Offstage 藏起來而不是整個換成別的元件，
      // 才能保留同一個 iframe 實例（不重新註冊、不重新載入），收合
      // 期間播放不中斷，展開回來還接續在原本的進度。
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Offstage(offstage: _collapsed, child: _buildPanel()),
          if (_collapsed) _buildBubble(),
        ],
      ),
    );
  }

  Offset _clamp(Offset pos, Size screen, Size size) {
    // maxScrollExtent 之類的算法在螢幕還沒 layout 完（size 是 0）時會
    // 算出負的上限，clamp 下限又比上限大會直接丟例外，先擋掉這個邊界。
    final maxX = (screen.width - size.width).clamp(0.0, double.infinity);
    final maxY = (screen.height - size.height).clamp(0.0, double.infinity);
    return Offset(pos.dx.clamp(0, maxX), pos.dy.clamp(0, maxY));
  }

  void _onDragUpdate(DragUpdateDetails details, Size screen, Size size) {
    setState(() {
      _position = _clamp(_position! + details.delta, screen, size);
    });
  }

  Widget _buildBubble() {
    // 泡泡本身是純 Flutter 畫的圖示，故意不放影片畫面進來——影片內容是
    // 跨網域 iframe，會直接吃掉點在它上面的觸控（沒辦法跟我們自己的
    // 拖曳手勢共存，見同一天跟使用者討論子母視窗那次的結論），縮成一顆
    // 純圖示才能保證拖曳／點擊一定準。
    return GestureDetector(
      onPanUpdate: (d) => _onDragUpdate(
        d,
        MediaQuery.sizeOf(context),
        const Size(_bubbleSize, _bubbleSize),
      ),
      onTap: () => setState(() => _collapsed = false),
      child: Container(
        width: _bubbleSize,
        height: _bubbleSize,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.ytPinAccent, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.smart_display_rounded,
          color: AppColors.ink,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _panelWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassEdge),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 只有這條標題列能拖，不是整個面板——影片區塊底下是真正的
            // YouTube iframe，直接蓋在上面的手勢偵測搶不贏瀏覽器原生
            // 元素，點在影片上想拖會拖不動、也會誤觸播放器自己的控制項。
            GestureDetector(
              onPanUpdate: (d) => _onDragUpdate(
                d,
                MediaQuery.sizeOf(context),
                const Size(_panelWidth, _panelHeight),
              ),
              child: SizedBox(
                height: _headerHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.drag_indicator_rounded,
                        size: 16,
                        color: AppColors.ink3,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            openExternalUrl(context, widget.watchUrl),
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        color: AppColors.ink2,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        tooltip: '在 YouTube 開啟',
                      ),
                      IconButton(
                        onPressed: () => setState(() => _collapsed = true),
                        icon: const Icon(Icons.remove_rounded, size: 15),
                        color: AppColors.ink2,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        tooltip: '收合成小圖示',
                      ),
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, size: 15),
                        color: AppColors.ink2,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        tooltip: '關閉',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _panelVideoHeight,
              width: _panelWidth,
              child: buildYtEmbeddedPlayer(widget.videoId),
            ),
          ],
        ),
      ),
    );
  }
}

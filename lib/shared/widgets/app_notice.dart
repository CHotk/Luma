import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';

/// 全 App 統一的提示訊息，取代 Flutter 內建的 [SnackBar]——後者是純白、
/// 從畫面底部滑上來的樣式，跟這個 App 全站深色毛玻璃的視覺完全不搭
/// （2026-09-23 使用者回饋：「同步成功的提示也太醜吧怎純白的從下面
/// 出來」）。改成從**頂部**滑下來、跟 [GlassCard] 同一套毛玻璃質感
/// （模糊背景＋半透明深底＋亮邊），這是全 App 唯一該用的提示元件，
/// 不要在個別頁面各自組 [SnackBar]。
///
/// 用法：`showAppNotice(context, '已完成')`，跟原本
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))`
/// 是同一個使用時機，只是換一顆函式呼叫。
///
/// [detail] 是第二行灰色小字（例如同步有失敗時的「其他功能已經更新」），
/// 不給就只有一行。
///
/// [overlay] 給「頁面已經關掉、手上只有整個 App 的 Navigator」的情況用
/// （例如同步在背景跑完，使用者早就離開同步頁）：Navigator 自己的
/// context 往上找不到 Overlay（Overlay 在它底下），直接 `Overlay.of` 會
/// 「Null check operator used on a null value」當掉——2026-10-12 使用者
/// 貼的同步紀錄「意外錯誤」就是這個，背景同步完的通知也因此從來沒出現。
/// 這時改傳 `rootNavigatorKey.currentState?.overlay`。
Future<void> showAppNotice(
  BuildContext context,
  String message, {
  String? detail,
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  OverlayState? overlay,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  overlay ??= Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
    if (!completer.isCompleted) completer.complete();
  }

  entry = OverlayEntry(
    builder: (context) => _AppNoticeOverlay(
      message: message,
      detail: detail,
      isError: isError,
      duration: duration,
      onDismissed: remove,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _AppNoticeOverlay extends StatefulWidget {
  const _AppNoticeOverlay({
    required this.message,
    required this.detail,
    required this.isError,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? detail;
  final bool isError;
  final Duration duration;
  final VoidCallback onDismissed;

  /// 右邊一顆動作鈕（例如「復原」，2026-10-14 播放清單移除影片用）。
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_AppNoticeOverlay> createState() => _AppNoticeOverlayState();
}

class _AppNoticeOverlayState extends State<_AppNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _autoDismissTimer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    _autoDismissTimer?.cancel();
    if (!mounted) {
      widget.onDismissed();
      return;
    }
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Gap.screenSide,
            10,
            Gap.screenSide,
            0,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1.4),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: GestureDetector(
                onTap: _dismiss,
                child: _NoticeCard(
                  message: widget.message,
                  detail: widget.detail,
                  isError: widget.isError,
                  actionLabel: widget.actionLabel,
                  onAction: widget.onAction == null
                      ? null
                      : () {
                          widget.onAction!();
                          _dismiss();
                        },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    required this.detail,
    required this.isError,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? detail;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final accentColor = isError ? AppColors.bad : AppColors.ok;
    final shape = BorderRadius.circular(16);
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xE0141220),
              borderRadius: shape,
              border: Border.all(color: AppColors.glassEdge),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            // 圖示＋文字整組置中（2026-10-02 使用者挑「確認對話框與提示」
            // 第 2 版時要求文字居中，跟 [showAppConfirmDialog] 一致）。
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: accentColor,
                ),
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.ink2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(width: Gap.sm),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

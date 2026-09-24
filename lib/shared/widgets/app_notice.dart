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
Future<void> showAppNotice(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
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
      isError: isError,
      duration: duration,
      onDismissed: remove,
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _AppNoticeOverlay extends StatefulWidget {
  const _AppNoticeOverlay({
    required this.message,
    required this.isError,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final bool isError;
  final Duration duration;
  final VoidCallback onDismissed;

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
                  isError: widget.isError,
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
  const _NoticeCard({required this.message, required this.isError});

  final String message;
  final bool isError;

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
            child: Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: accentColor,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
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

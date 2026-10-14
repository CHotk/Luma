import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/nav_bar_prefs_store.dart';
import '../features/yt_tracker/yt_playlist_actions.dart';
import '../shared/widgets/floating_tab_bar.dart';
import 'providers.dart';
import 'router.dart';

/// 記著現在有幾個對話框／底部面板開著——開著的時候分頁列先藏起來，
/// 不然會蓋在面板上面（分頁列畫在整個 Navigator 外面）。
class NavBarRouteObserver extends NavigatorObserver {
  final popups = ValueNotifier<int>(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) popups.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) popups.value = math.max(0, popups.value - 1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) popups.value = math.max(0, popups.value - 1);
  }
}

final navBarRouteObserver = NavBarRouteObserver();

/// 一條分頁列要畫什麼。
class _NavSpec {
  const _NavSpec(this.tabs, this.selected, this.onTap, {this.onLongPress});

  final List<FloatingTab> tabs;
  final int? selected;
  final ValueChanged<int> onTap;
  final ValueChanged<int>? onLongPress;
}

/// 底部浮動分頁列（2026-10-14 使用者要求，設計稿第 2 版 iOS 26 膠囊）。
/// 放在 `MaterialApp.router` 的 builder 裡，整個 App 一條：
///
/// - **全 App 共用**（預設）：英文／日文／YT 三格，在各功能首頁（跟 App
///   首頁）顯示。
/// - **各功能自己的**：YT 是頻道／影片（設定選的某個頻道，當快捷）／播放
///   清單，YT 裡每一頁都顯示；其他功能還沒有自己的，就不顯示。
/// - **不顯示**。
///
/// 設定跨裝置同步（[NavBarPrefs]）。往下滑縮成一顆、往上滑展開；對話框、
/// 底部面板、鍵盤出來時藏起來。顯示時頁面底部的安全區加高，頁面內容
/// 不會被擋住。
class AppBottomNavFrame extends ConsumerStatefulWidget {
  const AppBottomNavFrame({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppBottomNavFrame> createState() => _AppBottomNavFrameState();
}

class _AppBottomNavFrameState extends ConsumerState<AppBottomNavFrame> {
  bool _collapsed = false;
  String? _lastPath;

  static const _globalTabs = [
    FloatingTab(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      label: '英文',
    ),
    FloatingTab(
      icon: Icons.draw_outlined,
      selectedIcon: Icons.draw_rounded,
      label: '日文',
    ),
    FloatingTab(
      icon: Icons.subscriptions_outlined,
      selectedIcon: Icons.subscriptions_rounded,
      label: 'YT',
    ),
  ];

  static const _ytTabs = [
    FloatingTab(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: '頻道',
    ),
    FloatingTab(
      icon: Icons.smart_display_outlined,
      selectedIcon: Icons.smart_display_rounded,
      label: '影片',
    ),
    FloatingTab(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
      label: '播放清單',
    ),
  ];

  static String _path() =>
      appRouter.routerDelegate.currentConfiguration.uri.path;

  _NavSpec? _spec(String path, NavBarMode mode, String videoChannelId) {
    switch (mode) {
      case NavBarMode.off:
        return null;
      case NavBarMode.global:
        const roots = ['/start', '/home', '/jp-home', '/yt-tracker'];
        if (!roots.contains(path)) return null;
        final selected = switch (path) {
          '/home' => 0,
          '/jp-home' => 1,
          '/yt-tracker' => 2,
          _ => null,
        };
        return _NavSpec(_globalTabs, selected, (i) {
          if (i == selected) return;
          final settings = ref.read(settingsRepositoryProvider);
          switch (i) {
            case 0:
              settings.saveLastTrack('en');
              appRouter.go('/home');
            case 1:
              settings.saveLastTrack('ja');
              appRouter.go('/jp-home');
            default:
              appRouter.go('/yt-tracker');
          }
        });
      case NavBarMode.feature:
        final isYt =
            path.startsWith('/yt-tracker') || path.startsWith('/yt-playlists');
        if (!isYt) return null;
        final selected = path.startsWith('/yt-playlists')
            ? 2
            : (videoChannelId.isNotEmpty &&
                  path == '/yt-tracker/channel/$videoChannelId')
            ? 1
            : 0;
        return _NavSpec(
          _ytTabs,
          selected,
          (i) => _onYtTab(i, path, videoChannelId),
          // 長按「影片」換頻道。
          onLongPress: (i) {
            if (i == 1) _pickVideoChannel();
          },
        );
    }
  }

  Future<void> _pickVideoChannel() async {
    final ctx = rootNavigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;
    final id = await pickVideoTabChannel(ctx, ref);
    if (id != null) appRouter.go('/yt-tracker/channel/$id');
  }

  void _onYtTab(int i, String path, String videoChannelId) {
    switch (i) {
      case 0:
        // 再點一次也回到頻道第一層。
        if (path != '/yt-tracker') appRouter.go('/yt-tracker');
      case 1:
        if (videoChannelId.isEmpty) {
          _pickVideoChannel();
        } else {
          appRouter.go('/yt-tracker/channel/$videoChannelId');
        }
      default:
        if (path != '/yt-playlists') appRouter.go('/yt-playlists');
    }
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final d = n.scrollDelta ?? 0;
    if (d > 3 && n.metrics.pixels > 60 && !_collapsed) {
      setState(() => _collapsed = true);
    } else if (d < -3 && _collapsed) {
      setState(() => _collapsed = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(navBarPrefsProvider).mode;
    final videoChannelId = ref.watch(
      ytDisplayPrefsProvider.select((p) => p.videoTabChannelId),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([
        appRouter.routerDelegate,
        navBarRouteObserver.popups,
      ]),
      builder: (context, _) {
        final path = _path();
        if (path != _lastPath) {
          // 換頁就展開回來。
          _lastPath = path;
          _collapsed = false;
        }
        final spec = _spec(path, mode, videoChannelId);
        final mq = MediaQuery.of(context);
        if (spec == null) return widget.child;
        final keyboard = mq.viewInsets.bottom > 0;
        final hidden = keyboard || navBarRouteObserver.popups.value > 0;
        final barBottom = math.max(mq.padding.bottom - 6, 12.0);
        final reserve = barBottom + FloatingTabBar.height + 8;
        return Stack(
          children: [
            NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScroll,
              child: MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(
                    bottom: math.max(mq.padding.bottom, reserve),
                  ),
                  viewPadding: mq.viewPadding.copyWith(
                    bottom: math.max(mq.viewPadding.bottom, reserve),
                  ),
                ),
                child: widget.child,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: barBottom,
              child: IgnorePointer(
                ignoring: hidden,
                child: AnimatedSlide(
                  offset: hidden ? const Offset(0, 1.6) : Offset.zero,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: hidden ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: FloatingTabBar(
                        tabs: spec.tabs,
                        selected: spec.selected,
                        onTap: spec.onTap,
                        onLongPress: spec.onLongPress,
                        collapsed: _collapsed,
                        onExpand: () => setState(() => _collapsed = false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

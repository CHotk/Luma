import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/nav_bar_prefs_store.dart';
import '../features/yt_tracker/yt_playlist_actions.dart';
import '../shared/nav_bar_hiders.dart';
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
/// - **各自功能**（預設）：有自己分頁列的功能（YT）顯示自己的，其他不顯示。
/// - **全 App 共用**：App 首頁、英文、日文首頁跟 YT 每一頁都是英文／日文／YT。
/// - **各自功能** 的 YT：YT 是頻道／影片（設定選的某個頻道，當快捷）／播放
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

  /// 日文自己的分頁列（2026-10-15 使用者選：首頁／手寫／考試；英日切換
  /// 標題旁的膠囊就有，不重複放）。
  static const _jpTabs = [
    FloatingTab(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: '首頁',
    ),
    FloatingTab(
      icon: Icons.draw_outlined,
      selectedIcon: Icons.draw_rounded,
      label: '手寫',
    ),
    FloatingTab(
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note_rounded,
      label: '考試',
    ),
  ];

  static bool _isJp(String path) =>
      path.startsWith('/jp-') ||
      path.startsWith('/kana-practice') ||
      path.startsWith('/kana-exam');

  _NavSpec? _jpSpec(String path) {
    // 正在作答時不擋手寫格子（多鄰國上課時也不顯示分頁列）。
    if (path == '/kana-exam/start') return null;
    final selected = path.startsWith('/kana-practice')
        ? 1
        : path.startsWith('/kana-exam')
        ? 2
        : 0;
    return _NavSpec(_jpTabs, selected, (i) {
      const targets = ['/jp-home', '/kana-practice', '/kana-exam'];
      if (path != targets[i]) appRouter.go(targets[i]);
    });
  }

  static String _path() => currentAppPath();

  _NavSpec? _spec(String path, NavBarMode mode, String videoChannelId) {
    final isYt =
        path.startsWith('/yt-tracker') || path.startsWith('/yt-playlists');
    switch (mode) {
      case NavBarMode.off:
        return null;
      case NavBarMode.global:
        // 全 App 共用就真的全 App 一條（2026-10-14 使用者回報：選了全局，
        // YT 裡面還是 YT 自己的）：App 首頁、英文、日文首頁跟 YT 每一頁都是
        // 英文／日文／YT。
        const roots = ['/start', '/home', '/jp-home'];
        if (!roots.contains(path) && !isYt) return null;
        final selected = isYt
            ? 2
            : switch (path) {
                '/home' => 0,
                '/jp-home' => 1,
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
        if (isYt) return _ytSpec(path, videoChannelId);
        return _isJp(path) ? _jpSpec(path) : null;
    }
  }

  /// YT 自己的分頁列：頻道／影片（設定選的某個頻道，當快捷）／播放清單。
  _NavSpec _ytSpec(String path, String videoChannelId) {
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

  Future<void> _pickVideoChannel() async {
    final ctx = rootNavigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;
    final id = await pickVideoTabChannel(ctx, ref);
    if (id != null) _openVideoChannel(id);
  }

  /// 「影片」那格開的頻道用疊上去的（2026-10-15 使用者回報：用換頁的
  /// 開過去，返回鍵沒作用），返回就回到點之前那頁。已經在那個頻道就不再疊。
  void _openVideoChannel(String id) {
    final target = '/yt-tracker/channel/$id';
    if (currentAppPath() == target) return;
    appRouter.push(target);
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
          _openVideoChannel(videoChannelId);
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
        navBarHiders,
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
        final keyboard = mq.viewInsets.bottom > 0;
        final hidden =
            spec == null ||
            keyboard ||
            navBarRouteObserver.popups.value > 0 ||
            navBarHiders.value > 0;
        // 離底部的距離（2026-10-14 使用者要求往上一點：原本貼著 Home 指示條）。
        final barBottom = math.max(mq.padding.bottom + 8, 26.0);
        // 浮在頁面上面，不佔一行（2026-10-14 使用者糾正）：頁面照樣排到最底，
        // 只是清單最後多留這麼高的空白（[FloatingNavInset]），最後一項才
        // 捲得上來、不被擋住。
        final reserve = spec == null
            ? 0.0
            : barBottom + FloatingTabBar.height + 12 - mq.padding.bottom;
        // 不管有沒有分頁列，結構都一樣，不然換頁時整個 App 會被重建。
        return Stack(
          children: [
            NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScroll,
              child: FloatingNavInset(value: reserve, child: widget.child),
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
                    // 分頁列畫在整個 App 的 Navigator 外面，沒有 Material，
                    // 文字會出現黃色雙底線（2026-10-14 使用者回報），補一層。
                    child: Material(
                      type: MaterialType.transparency,
                      child: Center(
                        child: spec == null
                            ? const SizedBox.shrink()
                            : FloatingTabBar(
                                tabs: spec.tabs,
                                selected: spec.selected,
                                onTap: spec.onTap,
                                onLongPress: spec.onLongPress,
                                collapsed: _collapsed,
                                onExpand: () =>
                                    setState(() => _collapsed = false),
                              ),
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

/// 底部浮動分頁列擋住的高度（扣掉本來的安全區）。有分頁列的頁面在清單
/// 最後加這麼高的空白，最後一項才捲得到分頁列上面；沒有分頁列時是 0。
class FloatingNavInset extends InheritedWidget {
  const FloatingNavInset({
    super.key,
    required this.value,
    required super.child,
  });

  final double value;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FloatingNavInset>()?.value ??
      0;

  @override
  bool updateShouldNotify(FloatingNavInset old) => old.value != value;
}

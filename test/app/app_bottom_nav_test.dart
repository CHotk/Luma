import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/app_bottom_nav.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/app/router.dart';
import 'package:lume/data/repositories/nav_bar_prefs_store.dart';
import 'package:lume/shared/nav_bar_hiders.dart';
import 'package:lume/shared/widgets/floating_tab_bar.dart';

import '../support/app_host.dart';
import '../support/poke.dart';
import '../support/yt_fake.dart';

/// 底部浮動分頁列（2026-11-13 第 19 項）：各自功能（YT、日文、音樂、記帳）、
/// 全 App 共用、不顯示三種模式每一格都點；再點目前那格不動；YT「影片」沒選頻道
/// 先跳選單、長按換頻道；對話框、鍵盤、[navBarHiders] 出來時藏起來；往下滑縮成
/// 一顆、點它展開、往上滑展開；換頁展開回來。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  Finder bar() => find.byType(FloatingTabBar);
  Finder tab(String label) =>
      find.descendant(of: bar(), matching: find.text(label));

  bool hidden(WidgetTester tester) => tester
      .widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(AnimatedSlide),
              matching: find.byType(IgnorePointer),
            )
            .first,
      )
      .ignoring;

  FloatingTabBar barWidget(WidgetTester tester) =>
      tester.widget<FloatingTabBar>(bar());

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(tab(label));
    await settle(tester, 5);
  }

  void setMode(ProviderContainer c, NavBarMode mode) =>
      c.read(navBarPrefsProvider.notifier).state = NavBarPrefs(
        mode: mode,
        updatedAt: DateTime.now(),
      );

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(() async {
        await body();
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      }, () => FakeYoutube().client());

  testWidgets('各自功能：YT 三格、影片沒選頻道先選、長按換頻道、再點同一格不動', (tester) async {
    await run(tester, () async {
      final (_, c) = await openWholeApp(tester);
      await goPath(tester, '/yt-tracker');
      expect(barWidget(tester).selected, 0);
      await tapTab(tester, '播放清單');
      expect(currentAppPath(), '/yt-playlists');
      await tapTab(tester, '播放清單');
      expect(currentAppPath(), '/yt-playlists');
      await tapTab(tester, '頻道');
      expect(currentAppPath(), '/yt-tracker');
      await tapTab(tester, '頻道');
      expect(currentAppPath(), '/yt-tracker');

      // 影片：還沒選頻道 → 跳選單；不選關掉什麼都不變。
      await tapTab(tester, '影片');
      await settle(tester, 4);
      expect(find.text('頻道a'), findsWidgets);
      await closeOverlays(tester);
      expect(currentAppPath(), '/yt-tracker');
      expect(c.read(ytDisplayPrefsProvider).videoTabChannelId, '');

      // 再點一次，選頻道a → 疊上去那個頻道，之後「影片」那格亮。
      await tapTab(tester, '影片');
      await settle(tester, 4);
      await tester.tap(find.text('頻道a').last);
      await settle(tester, 6);
      expect(c.read(ytDisplayPrefsProvider).videoTabChannelId, 'a');
      expect(currentAppPath(), '/yt-tracker/channel/a');
      expect(barWidget(tester).selected, 1);
      // 已經在那個頻道，再點不再疊。
      await tapTab(tester, '影片');
      expect(currentAppPath(), '/yt-tracker/channel/a');
      await tapTab(tester, '頻道');
      expect(currentAppPath(), '/yt-tracker');
      // 選過頻道：點「影片」直接開。
      await tapTab(tester, '影片');
      expect(currentAppPath(), '/yt-tracker/channel/a');

      // 長按「影片」跳換頻道選單；長按別格沒反應。
      await tester.longPress(tab('頻道'));
      await settle(tester, 4);
      await tester.longPress(tab('影片'));
      await settle(tester, 5);
      expect(find.byType(BottomSheet), findsOneWidget);
      // 選回同一個頻道：已經在那頁，不再疊一層。
      await tester.tap(find.text('頻道a').last);
      await settle(tester, 6);
      expect(c.read(ytDisplayPrefsProvider).videoTabChannelId, 'a');
      expect(currentAppPath(), '/yt-tracker/channel/a');
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  testWidgets('各自功能：日文三格（考試作答中不顯示）、音樂三格、記帳四格、其他功能沒有', (tester) async {
    await run(tester, () async {
      await openWholeApp(tester);
      await goPath(tester, '/jp-home');
      expect(barWidget(tester).selected, isNull);
      for (final (label, path) in [
        ('手寫', '/kana-practice'),
        ('考試', '/kana-exam'),
        ('點亮', '/jp-light'),
      ]) {
        await tapTab(tester, label);
        expect(currentAppPath(), path);
        await tapTab(tester, label);
        expect(currentAppPath(), path);
      }
      await goPath(tester, '/kana-exam/start', extra: 'あ');
      expect(hidden(tester), isTrue);

      await goPath(tester, '/music/log');
      expect(barWidget(tester).selected, isNull);
      for (final (label, path) in [
        ('搜尋', '/music/search'),
        ('音樂庫', '/music/library'),
        ('首頁', '/music'),
      ]) {
        await tapTab(tester, label);
        expect(currentAppPath(), path);
        await tapTab(tester, label);
      }

      await goPath(tester, '/ledger/accounts');
      for (final (label, path) in [
        ('首頁', '/ledger'),
        ('明細', '/ledger/list'),
        ('統計', '/ledger/stats'),
        ('帳戶', '/ledger/accounts'),
      ]) {
        await tapTab(tester, label);
        expect(currentAppPath(), path);
        await tapTab(tester, label);
      }
      // 記帳操作紀錄、訂閱、其他沒有自己分頁列的功能：不顯示。
      for (final p in ['/ledger/log', '/ledger/subs', '/diary', '/start']) {
        await goPath(tester, p);
        expect(hidden(tester), isTrue, reason: p);
      }
    });
  });

  testWidgets('全 App 共用：英文／日文／YT 三格；非首頁沒有；不顯示模式（記帳照樣有）', (tester) async {
    await run(tester, () async {
      final (_, c) = await openWholeApp(tester);
      setMode(c, NavBarMode.global);
      await goPath(tester, '/start');
      expect(barWidget(tester).selected, isNull);
      await tapTab(tester, '英文');
      expect(currentAppPath(), '/home');
      expect(barWidget(tester).selected, 0);
      await tapTab(tester, '英文');
      expect(currentAppPath(), '/home');
      await tapTab(tester, '日文');
      expect(currentAppPath(), '/jp-home');
      expect(barWidget(tester).selected, 1);
      await tapTab(tester, 'YT');
      expect(currentAppPath(), '/yt-tracker');
      expect(barWidget(tester).selected, 2);
      await goPath(tester, '/yt-playlists');
      expect(barWidget(tester).selected, 2);
      await goPath(tester, '/diary');
      expect(hidden(tester), isTrue);
      // 音樂照樣用自己的。
      await goPath(tester, '/music');
      expect(tab('音樂庫'), findsOneWidget);

      setMode(c, NavBarMode.off);
      await settle(tester, 3);
      for (final p in ['/yt-tracker', '/music', '/jp-home', '/start']) {
        await goPath(tester, p);
        expect(hidden(tester), isTrue, reason: p);
      }
      // 記帳就算關掉也照樣顯示（四個分頁只能從這條切）。
      await goPath(tester, '/ledger');
      expect(hidden(tester), isFalse);
    });
  });

  testWidgets('對話框、鍵盤、navBarHiders 出來時藏起來，關掉回來', (tester) async {
    await run(tester, () async {
      await openWholeApp(tester);
      await goPath(tester, '/yt-tracker');
      expect(hidden(tester), isFalse);

      final ctx = rootNavigatorKey.currentContext!;
      showDialog<void>(context: ctx, builder: (_) => const Text('對話框'));
      await settle(tester, 4);
      expect(navBarRouteObserver.popups.value, 1);
      expect(hidden(tester), isTrue);
      rootNavigatorKey.currentState!.pop();
      await settle(tester, 4);
      expect(navBarRouteObserver.popups.value, 0);
      expect(hidden(tester), isFalse);

      // 被移除（不是 pop）的對話框也要扣回來；不會扣到負的。
      showDialog<void>(context: ctx, builder: (_) => const Text('對話框'));
      await settle(tester, 4);
      final nav = rootNavigatorKey.currentState!;
      Route<dynamic>? top;
      nav.popUntil((r) {
        top ??= r;
        return true;
      });
      nav.removeRoute(top!);
      await settle(tester, 4);
      expect(navBarRouteObserver.popups.value, 0);
      navBarRouteObserver.didPop(top!, null);
      navBarRouteObserver.didRemove(top!, null);
      expect(navBarRouteObserver.popups.value, 0);

      navBarHiders.value++;
      await settle(tester, 2);
      expect(hidden(tester), isTrue);
      navBarHiders.value--;
      await settle(tester, 2);
      expect(hidden(tester), isFalse);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await settle(tester, 2);
      expect(hidden(tester), isTrue);
      tester.view.resetViewInsets();
      await settle(tester, 2);
      expect(hidden(tester), isFalse);
    });
  });

  testWidgets('往下滑縮成一顆、點它展開、往上滑展開；換頁展開回來；橫向捲動不算', (tester) async {
    await run(tester, () async {
      await openWholeApp(tester);
      await goPath(tester, '/yt-tracker');
      void scroll(double delta, double pixels, {Axis axis = Axis.vertical}) {
        final ctx = tester.element(find.byType(FloatingNavInset));
        ScrollUpdateNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 5000,
            pixels: pixels,
            viewportDimension: 800,
            axisDirection: axis == Axis.vertical
                ? AxisDirection.down
                : AxisDirection.right,
            devicePixelRatio: 3,
          ),
          context: ctx,
          scrollDelta: delta,
        ).dispatch(ctx);
      }

      scroll(10, 20); // 還沒捲超過 60，不縮。
      await settle(tester, 2);
      expect(barWidget(tester).collapsed, isFalse);
      scroll(10, 200, axis: Axis.horizontal);
      await settle(tester, 2);
      expect(barWidget(tester).collapsed, isFalse);
      scroll(10, 200);
      await settle(tester, 2);
      expect(barWidget(tester).collapsed, isTrue);
      scroll(10, 300); // 已經縮了，不再重畫。
      await settle(tester, 2);
      // 縮起來時點那一顆展開。
      await tester.tap(tab('頻道'));
      await settle(tester, 3);
      expect(barWidget(tester).collapsed, isFalse);
      scroll(10, 200);
      await settle(tester, 2);
      expect(barWidget(tester).collapsed, isTrue);
      scroll(-10, 150);
      await settle(tester, 2);
      expect(barWidget(tester).collapsed, isFalse);
      scroll(-10, 150); // 已經展開，不動。
      scroll(10, 200);
      await settle(tester, 2);
      expect(barWidget(tester).collapsed, isTrue);
      await goPath(tester, '/yt-playlists');
      expect(barWidget(tester).collapsed, isFalse);
      // 用滑鼠拖拉也能捲（App 的捲動設定）。
      await tester.dragFrom(
        const Offset(195, 500),
        const Offset(0, -200),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester, 3);
    });
  });

  test('FloatingNavInset：值變了才通知', () {
    const a = FloatingNavInset(value: 1, child: SizedBox());
    expect(
      a.updateShouldNotify(const FloatingNavInset(value: 1, child: SizedBox())),
      isFalse,
    );
    expect(
      a.updateShouldNotify(const FloatingNavInset(value: 2, child: SizedBox())),
      isTrue,
    );
  });

  testWidgets('FloatingNavInset.of：外面沒有就是 0', (tester) async {
    double? got;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          got = FloatingNavInset.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(got, 0);
  });
}

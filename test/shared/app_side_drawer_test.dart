import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lume/shared/debug/app_log.dart';
import 'package:lume/shared/nav_bar_hiders.dart';
import 'package:lume/shared/widgets/app_side_drawer.dart';

/// 左側選單（2026-11-13 第 19 項）：每一項從別的功能點進去會換到那個功能、在那個
/// 功能裡再點只關選單；目前那項亮起來；關閉鍵；除錯有新錯誤才冒紅點、看過就消；
/// 打開時藏底部分頁列、關掉放回來；圖示、大頭貼讀不到退回內建的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const items = {
    '首頁': '/start',
    '語言學習': '/home',
    '日記': '/diary',
    'YT 頻道追蹤': '/yt-tracker',
    '音樂': '/music',
    '記帳': '/ledger',
    '健身': '/fitness',
    '交易&自律': '/crypto-watch',
    '負債管理': '/debt',
    'i88': '/i88',
    '抽菸記錄': '/smoking-log',
    '喝酒記錄': '/drinking-log',
    '本機儲存': '/local-storage',
    '多裝置同步': '/sync',
    '除錯': '/debug-log',
  };

  Future<GoRouter> open(
    WidgetTester tester,
    String at, {
    AssetBundle? bundle,
  }) async {
    tester.view.physicalSize = const Size(400, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: at,
      routes: [
        for (final p in {...items.values, '/jp-home'})
          GoRoute(
            path: p,
            builder: (_, _) =>
                Scaffold(drawer: const AppSideDrawer(), body: Text('page:$p')),
          ),
      ],
    );
    final app = MaterialApp.router(routerConfig: router);
    await tester.pumpWidget(
      bundle == null ? app : DefaultAssetBundle(bundle: bundle, child: app),
    );
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    return router;
  }

  String path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;
  bool drawerOpen(WidgetTester tester) =>
      tester.firstState<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen;

  Future<void> tapItem(WidgetTester tester, String label) async {
    final f = find.descendant(
      of: find.byType(AppSideDrawer),
      matching: find.text(label),
    );
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final MapEntry(key: label, value: target) in items.entries) {
    testWidgets('「$label」：從別的功能點進去換頁；已經在裡面再點只關選單', (tester) async {
      // 從日文首頁（算語言學習）出發；「語言學習」從日記出發。
      final from = label == '語言學習' ? '/diary' : '/jp-home';
      final r = await open(tester, from);
      await tapItem(tester, label);
      expect(path(r), target);
      expect(drawerOpen(tester), isFalse);

      tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      await tapItem(tester, label);
      expect(path(r), target);
      expect(drawerOpen(tester), isFalse);
    });
  }

  testWidgets('目前那項亮起來，其他不亮；敬請期待的點了沒反應', (tester) async {
    await open(tester, '/fitness');
    Material bg(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    expect(bg('健身').color, isNot(Colors.transparent));
    expect(bg('日記').color, Colors.transparent);
    expect(bg('語言學習').color, Colors.transparent);
    await tapItem(tester, '鬧鐘');
    expect(drawerOpen(tester), isTrue);
  });

  testWidgets('關閉鍵；打開時藏底部分頁列、關掉放回來', (tester) async {
    navBarHiders.value = 0;
    await open(tester, '/start');
    expect(navBarHiders.value, 1);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(drawerOpen(tester), isFalse);
    expect(navBarHiders.value, 0);
    // 已經是 0 還被拆掉一次：不會變負的。
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    navBarHiders.value = 0;
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(navBarHiders.value, 0);
  });

  testWidgets('除錯：看過之後才發生的錯誤才冒紅點；一般訊息不算', (tester) async {
    AppLog.markViewed();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await open(tester, '/start');
    Finder dot() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
          w.constraints?.maxWidth == 8,
    );
    expect(dot(), findsNothing);
    AppLog.add('一般訊息');
    await tester.pump();
    expect(dot(), findsNothing);
    AppLog.add('出錯了', isError: true);
    await tester.pump();
    expect(dot(), findsOneWidget);
  });

  testWidgets('圖示跟大頭貼讀不到：退回內建圖示、漸層圓點，不會壞', (tester) async {
    await open(tester, '/start', bundle: _BrokenBundle());
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 每張圖都讀不到的資產包。
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.png')) throw FlutterError('沒有這張圖：$key');
    return rootBundle.load(key);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';

/// 測試共用：記憶體版的本機儲存。
class MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// 讓非同步存檔（runAsync）跟畫面（pump）都跑一下。
Future<void> settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// 把 [page] 放進有 GoRouter 的 App（push 到不存在的路徑會到錯誤頁，[pokeAll] 會自己回來）。
Future<GoRouter> pumpPage(
  WidgetTester tester,
  MemoryStore store,
  Widget Function() page, {
  bool scroll = false,
  List<Override> overrides = const [],
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => scroll
            ? Scaffold(body: SingleChildScrollView(child: page()))
            : page(),
      ),
    ],
    errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(store), ...overrides],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await settle(tester);
  return router;
}

/// 有對話框、底部選單或推進去的頁面就關掉。
Future<void> closeOverlays(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    final navs = find.byType(Navigator);
    if (navs.evaluate().isEmpty) return;
    final nav = tester.state<NavigatorState>(navs.last);
    if (nav.canPop()) {
      nav.pop();
    } else {
      final root = tester.state<NavigatorState>(navs.first);
      if (!root.canPop()) return;
      root.pop();
    }
    await settle(tester, 2);
  }
}

/// 畫面上每個控制項（開關、勾選、選項、滑桿、按鈕、可點的列）依序點一次；
/// 跳出來的東西關掉、跑去別頁就回來。回傳點了幾個。[skip] 回 true 的不點
/// （例如會真的打網路、或測試另外測的）。
Future<int> pokeAll(
  WidgetTester tester,
  GoRouter router, {
  bool Function(Widget w)? skip,
  int max = 400,
}) async {
  Finder controls() => find.byWidgetPredicate(
    (w) =>
        (w is Switch ||
            w is Checkbox ||
            w is ChoiceChip ||
            w is FilterChip ||
            w is Slider ||
            w is TextButton ||
            w is OutlinedButton ||
            w is FilledButton ||
            w is ElevatedButton ||
            w is IconButton ||
            w is InkWell ||
            w is ListTile ||
            w is GestureDetector) &&
        !(skip?.call(w) ?? false),
  );
  final total = controls().evaluate().length;
  var tapped = 0;
  for (var i = 0; i < total && i < max; i++) {
    final all = controls();
    if (i >= all.evaluate().length) break;
    final f = all.at(i);
    final w = f.evaluate().single.widget;
    try {
      await tester.ensureVisible(f);
      await tester.pump();
    } catch (_) {
      continue;
    }
    if (w is Slider) {
      await tester.drag(f, const Offset(40, 0), warnIfMissed: false);
    } else {
      await tester.tap(f, warnIfMissed: false);
    }
    tapped++;
    await settle(tester, 3);
    await closeOverlays(tester);
    if (find.textContaining('route:').evaluate().isNotEmpty) {
      router.go('/');
      await settle(tester, 2);
    }
  }
  return tapped;
}

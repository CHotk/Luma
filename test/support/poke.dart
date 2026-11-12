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
/// （例如會真的打網路、或測試另外測的）。[deep]＝跳出來的表單裡也填字、點按鈕，選單逐項點。
Future<int> pokeAll(
  WidgetTester tester,
  GoRouter router, {
  bool Function(Widget w)? skip,
  int max = 400,
  bool deep = false,
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
    if (deep && _customMenuItems().evaluate().isNotEmpty) {
      // 自己畫的選單（泡泡選單、毛玻璃選單）：每一項都點一次，點完再打開同一顆。
      for (var k = 0; k < 12; k++) {
        if (k > 0) {
          final again = controls();
          if (i >= again.evaluate().length) break;
          try {
            await tester.ensureVisible(again.at(i));
            await tester.pump();
          } catch (_) {
            break;
          }
          await tester.tap(again.at(i), warnIfMissed: false);
          await settle(tester, 3);
        }
        final items = _customMenuItems();
        if (k >= items.evaluate().length) {
          await closeOverlays(tester);
          break;
        }
        await tester.tap(items.at(k), warnIfMissed: false);
        tapped++;
        await settle(tester, 3);
        await pokeOverlay(tester);
        await closeOverlays(tester);
        if (find.textContaining('route:').evaluate().isNotEmpty) {
          router.go('/');
          await settle(tester, 2);
        }
      }
      await _closeBubble(tester);
      continue;
    }
    if (deep) await pokeOverlay(tester);
    await closeOverlays(tester);
    if (find.textContaining('route:').evaluate().isNotEmpty) {
      router.go('/');
      await settle(tester, 2);
    }
  }
  if (deep) tapped += await pokeMenus(tester, router, max: max);
  return tapped;
}

/// 目前開著的自己畫的選單裡可以點的項目：泡泡選單（插在 Overlay），或是遮罩標籤
/// 是「關閉…」的 showGeneralDialog 選單（毛玻璃選單、時長選單）。沒有就是空的。
Finder _customMenuItems() {
  final bubble = find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('_BubbleMenuHost'),
  );
  if (bubble.evaluate().isNotEmpty) {
    return find.descendant(of: bubble.last, matching: find.byType(InkWell));
  }
  final barrier = find.byWidgetPredicate(
    (w) => w is ModalBarrier && (w.semanticsLabel ?? '').startsWith('關閉'),
  );
  if (barrier.evaluate().isEmpty) return find.byKey(const ValueKey('_none_'));
  final scopes = find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('_ModalScope'),
  );
  return find.descendant(of: scopes.last, matching: find.byType(InkWell));
}

/// 泡泡選單還開著（沒選就關）：點外面的遮罩收掉。
Future<void> _closeBubble(WidgetTester tester) async {
  final bubble = find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('_BubbleMenuHost'),
  );
  if (bubble.evaluate().isEmpty) return;
  await tester.tapAt(const Offset(4, 4));
  await settle(tester, 2);
}

/// 表單裡的按鈕輪流從前面點、從後面點：從後面點通常先按到「確定／刪除」，
/// 從前面點通常是「取消」，兩條路都會走到。
var _overlayFromEnd = false;

bool _isControl(Widget w) =>
    w is Switch ||
    w is Checkbox ||
    w is ChoiceChip ||
    w is FilterChip ||
    w is TextButton ||
    w is OutlinedButton ||
    w is FilledButton ||
    w is IconButton ||
    w is ListTile ||
    w is InkWell;

/// 有對話框或底部表單開著：每個輸入框打 [text]、裡面的控制項依序點一次（點了關掉就停）。
Future<void> pokeOverlay(
  WidgetTester tester, {
  String text = '12',
  int max = 25,
}) async {
  Finder host() => find.byWidgetPredicate(
    (w) => w is Dialog || w is AlertDialog || w is BottomSheet,
  );
  if (host().evaluate().isEmpty) return;
  final fields = find.descendant(
    of: host().last,
    matching: find.byType(TextField),
  );
  for (var i = 0; i < fields.evaluate().length && i < 8; i++) {
    try {
      await tester.enterText(fields.at(i), text);
      await tester.pump();
    } catch (_) {}
  }
  _overlayFromEnd = !_overlayFromEnd;
  final fromEnd = _overlayFromEnd;
  for (var j = 0; j < max; j++) {
    if (host().evaluate().isEmpty) return;
    final inner = find.descendant(
      of: host().last,
      matching: find.byWidgetPredicate(_isControl),
    );
    final count = inner.evaluate().length;
    if (j >= count) return;
    final at = inner.at(fromEnd ? count - 1 - j : j);
    try {
      await tester.ensureVisible(at);
      await tester.pump();
      await tester.tap(at, warnIfMissed: false);
    } catch (_) {
      continue;
    }
    await settle(tester, 2);
  }
}

/// 每個選單（PopupMenuButton）打開、逐項點一次；點完跳出來的表單也照 [pokeOverlay] 點過。
Future<int> pokeMenus(
  WidgetTester tester,
  GoRouter router, {
  int max = 400,
}) async {
  Finder menus() => find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('PopupMenuButton'),
  );
  var tapped = 0;
  final total = menus().evaluate().length;
  for (var i = 0; i < total && tapped < max; i++) {
    for (var k = 0; k < 20 && tapped < max; k++) {
      final m = menus();
      if (i >= m.evaluate().length) break;
      try {
        await tester.ensureVisible(m.at(i));
        await tester.pump();
        await tester.tap(m.at(i), warnIfMissed: false);
      } catch (_) {
        break;
      }
      await settle(tester, 2);
      final items = find.byWidgetPredicate(
        (w) =>
            w.runtimeType.toString().startsWith('PopupMenuItem') ||
            w.runtimeType.toString().startsWith('CheckedPopupMenuItem'),
      );
      if (k >= items.evaluate().length) {
        await closeOverlays(tester);
        break;
      }
      await tester.tap(items.at(k), warnIfMissed: false);
      tapped++;
      await settle(tester, 3);
      await pokeOverlay(tester);
      await closeOverlays(tester);
      if (find.textContaining('route:').evaluate().isNotEmpty) {
        router.go('/');
        await settle(tester, 2);
      }
    }
  }
  return tapped;
}

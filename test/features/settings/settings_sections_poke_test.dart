import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/settings/other_settings_page.dart';
import 'package:lume/features/settings/settings_page.dart';

/// 設定的每一段（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：每個開關、選項、
/// 滑桿、按鈕都點一次——不會出錯，跳出來的對話框／頁面關得掉，開關改了會存起來。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sections = <String, Widget Function()>{
    '一般': () => const AppHomeSettingsSection(),
    '英文': () => const EnglishSettingsSection(),
    '日文': () => const JpSettingsSection(),
    'YT': () => const YtSettingsSection(),
    '音樂': () => const MusicSettingsSection(),
    '交易&自律': () => const TradeSettingsSection(),
    '記帳': () => const LedgerSettingsSection(),
    'i88': () => const I88SettingsSection(),
    '日記／負債（要舊密碼）': () => const LockSettingsSection(askCurrent: true),
    '日記／負債': () => const LockSettingsSection(askCurrent: false),
    '雲端同步': () => const SyncSettingsSection(),
  };

  Future<void> settle(WidgetTester tester, [int n = 4]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// 有對話框、底部選單或推進去的頁面就關掉，回到設定那一段。
  Future<void> closeOverlays(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      final navs = find.byType(Navigator);
      if (navs.evaluate().isEmpty) return;
      final nav = tester.state<NavigatorState>(navs.last);
      if (!nav.canPop()) {
        final root = tester.state<NavigatorState>(navs.first);
        if (!root.canPop()) return;
        root.pop();
      } else {
        nav.pop();
      }
      await settle(tester, 2);
    }
  }

  for (final MapEntry(key: name, value: build) in sections.entries) {
    testWidgets('設定「$name」：每個控制項點一次都不會壞、開關會存', (tester) async {
      final store = _MemoryStore();
      tester.view.physicalSize = const Size(420 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                Scaffold(body: SingleChildScrollView(child: build())),
          ),
        ],
        errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await settle(tester);

      Finder controls() => find.byWidgetPredicate(
        (w) =>
            w is Switch ||
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
            w is ListTile,
      );

      final total = controls().evaluate().length;
      expect(total, greaterThan(0));
      final before = Map.of(store.data);
      var tapped = 0;
      for (var i = 0; i < total; i++) {
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
        // 跑到別的頁面（錯誤頁）也回來。
        if (find.textContaining('route:').evaluate().isNotEmpty) {
          router.go('/');
          await settle(tester, 2);
        }
      }
      expect(tapped, greaterThan(0));
      expect(tester.takeException(), isNull);
      // 至少有一個設定被改過存起來（純按鈕的段落不一定有）。
      if (find.byType(Switch).evaluate().isNotEmpty) {
        expect(store.data, isNot(equals(before)));
      }
      await tester.pump(const Duration(seconds: 6));
    });
  }
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

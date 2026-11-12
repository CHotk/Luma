import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/diary_password_store.dart';
import 'package:lume/data/repositories/usdt_twd_rate_store.dart';
import 'package:lume/data/repositories/yt_stats_refresh_setting_store.dart';
import 'package:lume/features/settings/other_settings_page.dart';

import '../../support/poke.dart';

/// 設定裡要打字的地方（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：USDT 匯率
/// （不是數字、0、正常、改回預設）、日記／負債密碼（舊密碼錯、取消、新密碼空的、改成功）、
/// YT 訂閱人數更新頻率（加減、儲存）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('USDT 匯率：英文字打不進去、只有小數點／0 不能存；31.5 存起來；改回預設', (tester) async {
    final store = MemoryStore();
    await pumpPage(
      tester,
      store,
      () => const TradeSettingsSection(),
      scroll: true,
    );
    final field = find.byType(TextField).first;
    // 欄位本來就擋英文字；只打小數點也不是數字。
    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(find.text('abc'), findsNothing);
    await tester.enterText(field, '.');
    await tester.pump();
    expect(find.text('要大於 0 的數字'), findsOneWidget);
    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('要大於 0 的數字'), findsOneWidget);
    await tester.enterText(field, '31.5');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await settle(tester);
    expect(await tester.runAsync(() => UsdtTwdRateStore(store).load()), 31.5);
    expect(find.textContaining('已設定匯率'), findsOneWidget);
    final reset = find.textContaining('改回預設');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await settle(tester);
    expect(
      await tester.runAsync(() => UsdtTwdRateStore(store).load()),
      UsdtTwdRateStore.defaultRate,
    );
    // 按 Enter 也能存。
    await tester.enterText(field, '29');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(await tester.runAsync(() => UsdtTwdRateStore(store).load()), 29);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('密碼：舊密碼錯＝不給改；取消＝不改；新密碼空的不改；對了才改', (tester) async {
    final store = MemoryStore();
    await pumpPage(
      tester,
      store,
      () => const LockSettingsSection(askCurrent: true),
      scroll: true,
    );
    Future<void> openChange() async {
      await tester.tap(find.text('變更'));
      await settle(tester, 2);
    }

    // 舊密碼錯。
    await openChange();
    expect(find.text('先輸入目前的密碼'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '0000');
    await tester.tap(find.text('下一步'));
    await settle(tester);
    expect(find.text('密碼不對'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    // 第一步按取消。
    await openChange();
    await tester.tap(find.text('取消'));
    await settle(tester, 2);
    expect(find.text('變更日記／負債密碼'), findsNothing);
    // 舊密碼對（Enter 送出）、新密碼空的 → 不改。
    await openChange();
    await tester.enterText(
      find.byType(TextField).last,
      DiaryPasswordStore.defaultPassword,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('變更日記／負債密碼'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(
      await tester.runAsync(() => DiaryPasswordStore(store).loadPassword()),
      DiaryPasswordStore.defaultPassword,
    );
    // 再來一次，新密碼 2468 → 改好。
    await openChange();
    await tester.enterText(
      find.byType(TextField).last,
      DiaryPasswordStore.defaultPassword,
    );
    await tester.tap(find.text('下一步'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '2468');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(
      await tester.runAsync(() => DiaryPasswordStore(store).loadPassword()),
      '2468',
    );
    expect(find.text('已更新日記／負債密碼'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('YT 訂閱人數更新頻率：加一天、減一天、儲存（沒有頻道＝沒有要更新的）', (tester) async {
    final store = MemoryStore();
    await pumpPage(
      tester,
      store,
      () => const YtSettingsSection(),
      scroll: true,
    );
    final before = await tester.runAsync(
      () => YtStatsRefreshSettingStore(store).load(),
    );
    final add = find.byIcon(Icons.add).first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    await tester.tap(add);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pump();
    final save = find.ancestor(
      of: find.text('儲存'),
      matching: find.byType(FilledButton),
    );
    await tester.ensureVisible(save.first);
    await tester.tap(save.first);
    await settle(tester, 6);
    expect(
      await tester.runAsync(() => YtStatsRefreshSettingStore(store).load()),
      before! + 1,
    );
    expect(find.textContaining('已儲存'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}

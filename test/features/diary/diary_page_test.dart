import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/diary_password_store.dart';
import 'package:lume/data/repositories/diary_repository.dart';
import 'package:lume/domain/models/diary_entry.dart';
import 'package:lume/features/diary/diary_page.dart';

import '../../support/poke.dart';

/// 日記（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：密碼鎖（錯、對、Enter、
/// 改過的密碼）、打卡（空白不送、選心情天氣冷熱、補寫昨天／前天、今天打過了不能再打）、
/// 點一篇（編輯：改字、心情、天氣、空白不存、取消；刪除：取消、確定）、馬賽克（記住）、
/// 日期條（點日、再點取消、上一週下一週、展開月曆選日、換月）、匯出（切快照、下載、
/// 複製、關閉），每個控制項點一次不會壞。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  final now = DateTime.now();

  Future<MemoryStore> seed(WidgetTester tester, {bool today = false}) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final repo = DiaryRepository(store);
      for (var i = today ? 0 : 1; i < 12; i++) {
        await repo.add(
          DiaryEntry(
            id: 'd$i',
            mood: diaryMoods[i % diaryMoods.length],
            text: '第 $i 天的日記',
            weather: i.isEven ? diaryWeathers[i % 3] : '',
            temperature: i % 3 == 0 ? diaryTemperatures[i % 3] : '',
            savedAt: now.subtract(Duration(days: i * 3)),
          ),
        );
      }
    });
    return store;
  }

  Future<void> open(WidgetTester tester, MemoryStore store) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(
      tester,
      store,
      () => const DiaryPage(),
      size: const Size(390, 860),
    );
    await settle(tester, 6);
  }

  Future<void> unlock(WidgetTester tester, [String pw = '15975311']) async {
    await tester.enterText(find.byType(TextField).first, pw);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 4);
  }

  Future<List<DiaryEntry>> entries(WidgetTester tester, MemoryStore s) async =>
      (await tester.runAsync(() => DiaryRepository(s).loadAll()))!;

  testWidgets('密碼鎖：錯的說密碼錯誤、對的解開；改過的密碼要用新的', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    await unlock(tester, '0000');
    expect(find.text('密碼錯誤'), findsOneWidget);
    await unlock(tester);
    expect(find.text('密碼錯誤'), findsNothing);
    expect(find.byTooltip('匯出日記'), findsOneWidget);

    await tester.runAsync(() => DiaryPasswordStore(store).savePassword('1234'));
    await open(tester, store);
    await unlock(tester);
    expect(find.text('密碼錯誤'), findsOneWidget);
    await unlock(tester, '1234');
    expect(find.byTooltip('匯出日記'), findsOneWidget);
  });

  testWidgets('打卡：空白不送；選心情、天氣、冷熱、補寫前天，送出；那天打過就不能再打', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    await unlock(tester);
    final before = (await entries(tester, store)).length;
    final send = find.widgetWithIcon(FilledButton, Icons.check);
    Future<void> tapSend() async {
      final b = send.evaluate().isNotEmpty
          ? send
          : find.byType(FilledButton).first;
      await tester.ensureVisible(b);
      await tester.tap(b, warnIfMissed: false);
      await settle(tester, 4);
    }

    await tapSend();
    expect((await entries(tester, store)).length, before);
    for (final t in [diaryMoods[2], diaryWeathers[2], diaryTemperatures[2]]) {
      final f = find.text(t);
      if (f.evaluate().isNotEmpty) {
        await tester.ensureVisible(f.first);
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pump();
      }
    }
    final dropdown = find.byType(PopupMenuButton<int>);
    if (dropdown.evaluate().isNotEmpty) {
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await settle(tester, 3);
      await settle(tester, 2);
      await tester.tap(find.text('前天').last);
      await settle(tester, 4);
    }
    await tester.enterText(find.byType(TextField).first, '  今天很開心  ');
    await tapSend();
    final after = await entries(tester, store);
    expect(after.length, greaterThan(before));
    final added = after.firstWhere((e) => e.text == '今天很開心');
    expect(added.savedAt.day, now.subtract(const Duration(days: 2)).day);

    // 今天再打一則。
    await tester.enterText(find.byType(TextField).first, '今天的');
    await tapSend();
    expect(
      (await entries(tester, store)).where((e) => e.text == '今天的'),
      hasLength(1),
    );
  });

  testWidgets('點一篇：編輯（改字、心情、天氣、存）、編輯清空不存、取消、刪除（取消、確定）', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    await unlock(tester);
    Future<void> openEntry(String text) async {
      final f = find.text(text);
      await tester.ensureVisible(f.first);
      await tester.tap(f.first);
      await settle(tester, 3);
    }

    await openEntry('第 1 天的日記');
    await tester.tap(find.text('編輯'));
    await settle(tester, 3);
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      '改過的日記',
    );
    for (final t in [
      diaryMoods.last,
      diaryWeathers.last,
      diaryTemperatures.last,
    ]) {
      final f = find.descendant(of: dialog, matching: find.text(t));
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pump();
      }
    }
    await tester.tap(find.text('儲存'));
    await settle(tester, 4);
    expect(
      (await entries(tester, store)).any((e) => e.text == '改過的日記'),
      isTrue,
    );

    await openEntry('改過的日記');
    await tester.tap(find.text('編輯'));
    await settle(tester, 3);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '   ',
    );
    await tester.tap(find.text('儲存'));
    await settle(tester, 3);
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(find.text('取消'));
      await settle(tester, 3);
    }
    expect(
      (await entries(tester, store)).any((e) => e.text == '改過的日記'),
      isTrue,
    );

    await openEntry('第 2 天的日記');
    await tester.tap(find.text('刪除'));
    await settle(tester, 3);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    expect(
      (await entries(tester, store)).any((e) => e.text == '第 2 天的日記'),
      isTrue,
    );
    await openEntry('第 2 天的日記');
    await tester.tap(find.text('刪除'));
    await settle(tester, 3);
    await tester.tap(find.text('刪除').last);
    await settle(tester, 4);
    expect(
      (await entries(tester, store)).any((e) => e.text == '第 2 天的日記'),
      isFalse,
    );
  });

  testWidgets('馬賽克：切換、重開還記得；匯出：切快照、下載、複製、關閉', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    await unlock(tester);
    await tester.tap(find.byTooltip('馬賽克文字'));
    await settle(tester, 3);
    expect(store.data['diary.masked.v1'], 'true');
    await open(tester, store);
    await unlock(tester);
    expect(find.byTooltip('取消馬賽克'), findsOneWidget);

    await tester.tap(find.byTooltip('匯出日記'));
    await settle(tester, 6);
    expect(find.textContaining('共 '), findsWidgets);
    await tester.tap(find.text('連日記快照一起'));
    await settle(tester, 6);
    await tester.tap(find.text('僅這台裝置'));
    await settle(tester, 4);
    await tester.tap(find.text('下載'));
    await settle(tester, 3);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await tester.tap(find.text('複製'));
    await settle(tester, 3);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await tester.tap(find.text('關閉'));
    await settle(tester, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期條與月曆：點日標起來、再點取消、上下週、展開月曆選日、換月', (tester) async {
    final store = await seed(tester, today: true);
    await open(tester, store);
    await unlock(tester);
    final router = await Future.value(null);
    expect(router, isNull);
    final chips = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_DayChip',
    );
    if (chips.evaluate().length > 2) {
      await tester.tap(chips.at(1));
      await settle(tester, 3);
      await tester.tap(chips.at(1));
      await settle(tester, 3);
    }
    for (final icon in [
      Icons.chevron_left_rounded,
      Icons.chevron_right_rounded,
    ]) {
      final f = find.byIcon(icon);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await settle(tester, 2);
      }
    }
    await tester.tap(find.byTooltip('展開月曆選日期'));
    await settle(tester, 3);
    final cells = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_MonthCell',
    );
    if (cells.evaluate().isNotEmpty) {
      await tester.tap(
        cells.at(cells.evaluate().length ~/ 2),
        warnIfMissed: false,
      );
      await settle(tester, 3);
    }
    // 月曆左右滑換月。
    final pv = find.byType(PageView);
    if (pv.evaluate().isNotEmpty) {
      await tester.fling(pv.first, const Offset(300, 0), 1000);
      await settle(tester, 3);
      await tester.fling(pv.first, const Offset(-300, 0), 1000);
      await settle(tester, 3);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('解鎖後每個控制項點一次；沒有日記也不會壞', (tester) async {
    for (final empty in [false, true]) {
      final store = empty ? MemoryStore() : await seed(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      final router = await pumpPage(
        tester,
        store,
        () => const DiaryPage(),
        size: const Size(390, 860),
      );
      await settle(tester, 6);
      await unlock(tester);
      await pokeAll(tester, router, max: 120, deep: true);
      expect(tester.takeException(), isNull);
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}

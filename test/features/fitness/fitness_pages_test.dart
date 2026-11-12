import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/fitness_repository.dart';
import 'package:lume/domain/models/fitness.dart';
import 'package:lume/features/fitness/fitness_home_page.dart';
import 'package:lume/features/fitness/fitness_stats_page.dart';

import '../../support/poke.dart';

/// 健身（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：打卡（每種類型、選時間、
/// 選時長、補寫昨天）、點一筆（編輯：改類型、時間、時長、取消、儲存；刪除：取消、確定）、
/// 月曆換月、匯出（切快照、下載、複製、關閉）、統計頁；每個控制項點一次；
/// 沒資料、只有沒填時長的資料也不會壞；資料合併邊界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  final now = DateTime.now();

  Future<MemoryStore> seed(
    WidgetTester tester, {
    bool noDuration = false,
  }) async {
    final store = MemoryStore();
    await tester.runAsync(() async {
      final repo = FitnessRepository(store);
      for (var i = 1; i < 40; i++) {
        final d = now.subtract(Duration(days: i * 2));
        await repo.addEntry(
          FitnessEntry(
            id: 'f$i',
            date: DateTime(d.year, d.month, d.day),
            type: FitnessType.values[i % FitnessType.values.length],
            durationMinutes: noDuration || i % 4 == 0 ? null : 10 + i,
            loggedAt: d,
          ),
        );
      }
    });
    return store;
  }

  void quietPlatform(WidgetTester tester) {
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
  }

  Future<void> open(WidgetTester tester, MemoryStore store) async {
    quietPlatform(tester);
    await pumpPage(
      tester,
      store,
      () => const FitnessHomePage(),
      size: const Size(390, 860),
    );
    await settle(tester, 6);
  }

  Future<List<FitnessEntry>> entries(
    WidgetTester tester,
    MemoryStore s,
  ) async => (await tester.runAsync(() => FitnessRepository(s).loadEntries()))!;

  Future<void> done(WidgetTester tester) async {
    final b = find.text('完成');
    if (b.evaluate().isNotEmpty) {
      await tester.tap(b.last);
      await settle(tester, 3);
    }
  }

  testWidgets('打卡：每種類型、選時間、選時長、補寫昨天', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    final before = (await entries(tester, store)).length;
    for (final t in FitnessType.values) {
      final f = find.textContaining(t.label);
      if (f.evaluate().isEmpty) continue;
      await tester.ensureVisible(f.first);
      await tester.tap(f.first, warnIfMissed: false);
      await tester.pump();
    }
    // 補寫昨天。
    final dd = find.byType(PopupMenuButton<int>);
    if (dd.evaluate().isNotEmpty) {
      await tester.ensureVisible(dd.first);
      await tester.tap(dd.first);
      await settle(tester, 4);
      await tester.tap(find.text('昨天').last);
      await settle(tester, 3);
    }
    // 時間、時長的滾輪面板。
    for (final icon in [Icons.schedule_rounded, Icons.timer_outlined]) {
      final f = find.byIcon(icon);
      if (f.evaluate().isEmpty) continue;
      await tester.ensureVisible(f.first);
      await tester.tap(f.first, warnIfMissed: false);
      await settle(tester, 3);
      final wheels = find.byType(ListWheelScrollView);
      for (var i = 0; i < wheels.evaluate().length; i++) {
        await tester.drag(wheels.at(i), const Offset(0, -120));
        await settle(tester, 2);
      }
      await done(tester);
    }
    final check = find.textContaining('＋ 打卡');
    await tester.ensureVisible(check);
    await tester.tap(check);
    await settle(tester, 4);
    final after = await entries(tester, store);
    expect(after.length, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('點一筆：編輯（類型、時間、時長、取消、儲存）、刪除（取消、確定）', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    Future<void> openFirst() async {
      final rows = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_HistoryRow',
      );
      await tester.ensureVisible(rows.first);
      await tester.tap(rows.first);
      await settle(tester, 3);
    }

    await openFirst();
    await tester.tap(find.text('編輯'));
    await settle(tester, 3);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);

    await openFirst();
    await tester.tap(find.text('編輯'));
    await settle(tester, 3);
    final dialog = find.byType(AlertDialog);
    for (final t in FitnessType.values.reversed.take(2)) {
      final f = find.descendant(
        of: dialog,
        matching: find.textContaining(t.label),
      );
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pump();
      }
    }
    // 對話框裡的時間、時長。
    final inner = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate((w) => w is InkWell || w is ListTile),
    );
    for (var i = 0; i < inner.evaluate().length && i < 8; i++) {
      if (find.byType(AlertDialog).evaluate().isEmpty) break;
      final f = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate((w) => w is InkWell || w is ListTile),
      );
      if (i >= f.evaluate().length) break;
      await tester.tap(f.at(i), warnIfMissed: false);
      await settle(tester, 3);
      final wheels = find.byType(ListWheelScrollView);
      for (var k = 0; k < wheels.evaluate().length; k++) {
        await tester.drag(wheels.at(k), const Offset(0, -80));
        await settle(tester, 2);
      }
      await done(tester);
    }
    if (find.text('儲存').evaluate().isNotEmpty) {
      await tester.tap(find.text('儲存'));
      await settle(tester, 4);
    }

    final n = (await entries(tester, store)).length;
    await openFirst();
    await tester.tap(find.text('刪除'));
    await settle(tester, 3);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    expect((await entries(tester, store)).length, n);
    await openFirst();
    await tester.tap(find.text('刪除'));
    await settle(tester, 3);
    await tester.tap(find.text('刪除').last);
    await settle(tester, 4);
    expect((await entries(tester, store)).length, n - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月曆換月、匯出（切快照、下載、複製、關閉）', (tester) async {
    final store = await seed(tester);
    await open(tester, store);
    for (final icon in [
      Icons.chevron_left,
      Icons.chevron_left,
      Icons.chevron_right,
    ]) {
      await tester.tap(find.byIcon(icon).first, warnIfMissed: false);
      await settle(tester, 2);
    }
    await tester.tap(find.byTooltip('匯出打卡紀錄'));
    await settle(tester, 6);
    await tester.tap(find.text('連快照一起'));
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

  for (final (name, kind) in [('有資料', 0), ('沒資料', 1), ('都沒填時長', 2)]) {
    testWidgets('健身首頁、統計頁（$name）：每個控制項點一次', (tester) async {
      quietPlatform(tester);
      final store = kind == 1
          ? MemoryStore()
          : await seed(tester, noDuration: kind == 2);
      for (final page in [
        () => const FitnessHomePage(),
        () => const FitnessStatsPage(),
      ]) {
        final router = await pumpPage(
          tester,
          store,
          page,
          size: const Size(390, 860),
        );
        await settle(tester, 6);
        await pokeAll(tester, router, max: 100, deep: true);
        expect(tester.takeException(), isNull);
      }
      await tester.pump(const Duration(seconds: 5));
    });
  }

  test('資料：合併快照（快照贏）、雲端（本機贏、刪除贏、異動筆數）、匯出不含刪除、找不到 id 不動', () async {
    final repo = FitnessRepository(MemoryStore());
    FitnessEntry e(String id, FitnessType t, {DateTime? del}) => FitnessEntry(
      id: id,
      date: DateTime(2026, 10, 1),
      type: t,
      loggedAt: DateTime(2026, 10, 1, 8),
      deletedAt: del,
    );
    await repo.addEntry(e('a', FitnessType.running));
    await repo.addEntry(e('b', FitnessType.yoga));
    await repo.mergeSeed(const []);
    await repo.mergeSeed([
      e('a', FitnessType.squat),
      e('c', FitnessType.cardio),
    ]);
    expect(
      (await repo.loadEntries()).firstWhere((x) => x.id == 'a').type,
      FitnessType.squat,
    );
    expect(await repo.mergeFromCloud(const []), 0);
    final n = await repo.mergeFromCloud([
      e('b', FitnessType.yoga, del: DateTime(2026, 10, 2)),
      e('d', FitnessType.stretch),
    ]);
    expect(n, 2);
    expect((await repo.loadEntries()).any((x) => x.id == 'b'), isFalse);
    expect((await repo.allForUpload()).any((x) => x.id == 'b'), isTrue);
    expect(
      (await repo.loadAllIncludingDeleted()).length,
      (await repo.allForUpload()).length,
    );
    await repo.deleteEntry('沒有');
    await repo.updateEntry(e('沒有', FitnessType.pushup));
    await repo.updateEntry(e('c', FitnessType.pushup));
    final out = await repo.exportJson();
    expect(out.count, 3);
    expect(out.text, isNot(contains('"b"')));
  });
}

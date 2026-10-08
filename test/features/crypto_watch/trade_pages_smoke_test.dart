import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/crypto_watch_repository.dart';
import 'package:lume/data/repositories/trade_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/crypto_watch/crypto_watch_page.dart';
import 'package:lume/features/crypto_watch/trade_day_page.dart';
import 'package:lume/features/crypto_watch/trade_journal_page.dart';
import 'package:lume/features/crypto_watch/trade_report_page.dart';

/// 交易&自律四頁在手機寬度（360）畫得出來、不爆版，有資料跟沒資料都要。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_MemoryStore> seeded() async {
    final store = _MemoryStore();
    final now = DateTime.now();
    final trades = TradeRepository(store);
    await trades.add(
      symbol: 'BTC',
      isLong: false,
      leverage: 25,
      margin: 300,
      openedAt: now.subtract(const Duration(hours: 6)),
      closedAt: now.subtract(const Duration(hours: 1)),
      pnl: -120,
      note: '想追空，結果被軋',
    );
    await trades.add(
      symbol: 'DOGEUSDT',
      isLong: true,
      leverage: 5,
      margin: 1234567.5,
      openedAt: now.subtract(const Duration(days: 3)),
      closedAt: now.subtract(const Duration(hours: 2)),
      pnl: 98765.43,
    );
    await trades.add(
      symbol: 'ETH',
      isLong: true,
      leverage: 10,
      margin: 400,
      openedAt: now.subtract(const Duration(days: 1)),
    );
    await trades.setCapital(DateTime(now.year, now.month), 2000);
    final watches = CryptoWatchRepository(store);
    for (var i = 0; i < 12; i++) {
      await watches.add(at: now.subtract(Duration(minutes: 20 * i + 5)));
    }
    return store;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page,
    _MemoryStore store,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: MaterialApp(home: page),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> finish(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    // 主畫面有每秒的計時器，換掉畫面讓它收掉。
    await tester.pumpWidget(const SizedBox());
  }

  for (final empty in [false, true]) {
    final tag = empty ? '（沒資料）' : '（有資料）';

    testWidgets('主畫面$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pumpPage(tester, const CryptoWatchPage(), store);
      expect(find.text('交易&自律'), findsOneWidget);
      expect(find.text('距離上次看盤'), findsOneWidget);
      expect(find.text('看了（重新計時）'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pump();
      if (!empty) expect(find.textContaining('持倉中'), findsWidgets);
      if (!empty) expect(find.textContaining('月持倉期間'), findsOneWidget);
      expect(find.text('記一筆交易'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('月報兩個分頁$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pumpPage(tester, const TradeReportPage(), store);
      expect(find.text('看盤少的日子 vs 看盤多的日子'), findsOneWidget);
      await tester.tap(find.text('什麼樣的單在賺'));
      await tester.pump();
      if (!empty) expect(find.text('依槓桿'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('交易日誌$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pumpPage(tester, const TradeJournalPage(), store);
      expect(find.text(empty ? '還沒有交易紀錄' : '持倉中'), findsWidgets);
      await finish(tester);
    });

    testWidgets('某一天$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pumpPage(tester, TradeDayPage(day: DateTime.now()), store);
      expect(find.text('時間軸'), findsOneWidget);
      await finish(tester);
    });
  }

  testWidgets('記一筆表單填完才能存', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
    expect(find.text('記一筆開倉'), findsOneWidget);
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '儲存（持倉中）'),
    );
    expect(save().onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '400');
    await tester.pump();
    expect(find.textContaining('4,000 USDT'), findsOneWidget);
    expect(save().onPressed, isNotNull);
    await finish(tester);
  });

  testWidgets('補記：開倉時間一定有、打開「已經平倉了」多出平倉時間', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
    expect(find.text('開倉時間'), findsOneWidget);
    expect(find.text('平倉時間'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('已經平倉了（補記一整單）'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('已經平倉了（補記一整單）'));
    await tester.pumpAndSettle();
    expect(find.text('平倉時間'), findsOneWidget);
    expect(find.textContaining('持倉'), findsWidgets);
    await finish(tester);
  });

  test('平倉可以指定時間（補記以前的單）', () async {
    final repo = TradeRepository(_MemoryStore());
    final t = await repo.add(
      symbol: 'BTC',
      isLong: true,
      leverage: 10,
      margin: 100,
      openedAt: DateTime(2026, 9, 1, 9),
    );
    final at = DateTime(2026, 9, 3, 21, 40);
    final closed = await repo.close(t.id, pnl: 50, at: at);
    expect(closed!.closedAt, at);
    expect((await repo.loadAll()).single.closedAt, at);
  });

  testWidgets('設定月初資金後，月報酬馬上出現', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('${DateTime.now().month} 月初的資金'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '2000');
    await tester.tap(find.text('儲存'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('月初 2,000 ✎'), findsOneWidget);
    expect(find.textContaining('已設定'), findsOneWidget);
    expect(find.text('設定'), findsNothing);
    await finish(tester);
  });
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

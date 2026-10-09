import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/trade_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/trade_entry.dart';
import 'package:lume/domain/trade_stats.dart';
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
      leverage: 15,
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
    await tester.pumpWidget(const SizedBox());
  }

  for (final empty in [false, true]) {
    final tag = empty ? '（沒資料）' : '（有資料）';

    testWidgets('主畫面$tag', (tester) async {
      final store = empty ? _MemoryStore() : await seeded();
      await pumpPage(tester, const CryptoWatchPage(), store);
      expect(find.text('交易&自律'), findsOneWidget);
      // 最上面是當月損益卡，看盤卡片跟看盤次數都拿掉了。
      expect(find.text('${DateTime.now().month} 月已實現損益'), findsOneWidget);
      expect(find.text('距離上次看盤'), findsNothing);
      expect(find.textContaining('👁'), findsNothing);
      if (!empty) expect(find.text('+98,645.43'), findsWidgets);
      // USDT 後面有台幣換算（預設匯率 31）。
      if (!empty) expect(find.textContaining('≈ +NT\$'), findsWidgets);
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
      expect(find.text('槓桿 ≤ 10x vs > 10x'), findsOneWidget);
      expect(find.textContaining('看盤'), findsNothing);
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
      find.text('已經平倉了（補記以前的單）'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('已經平倉了（補記以前的單）'));
    await tester.pumpAndSettle();
    expect(find.text('平倉時間'), findsOneWidget);
    expect(find.textContaining('持倉'), findsWidgets);
    await finish(tester);
  });

  testWidgets('補記：沒有賺／賠按鈕，點 + 切成 −', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('已經平倉了（補記以前的單）'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('已經平倉了（補記以前的單）'));
    await tester.pumpAndSettle();
    // 背後主畫面月曆圖例也有「賺」「賠」，只看表單裡的。
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('賺')), findsNothing);
    expect(find.descendant(of: sheet, matching: find.text('賠')), findsNothing);
    final sign = find.byKey(const ValueKey('pnl-sign'));
    await tester.scrollUntilVisible(
      sign,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.descendant(of: sign, matching: find.text('+')), findsOneWidget);
    await tester.tap(sign);
    await tester.pump();
    expect(find.descendant(of: sign, matching: find.text('−')), findsOneWidget);
    // % 那格的符號跟著一起變，賺賠只有一個。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pct-sign')),
        matching: find.text('−'),
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('補記：開關緊接在槓桿後面，填 % 跟損益自動算出本金', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
    final sheetScroll = find.byType(Scrollable).last;
    final sw = find.text('已經平倉了（補記以前的單）');
    await tester.scrollUntilVisible(sw, 200, scrollable: sheetScroll);
    // 開關在本金輸入框上面。
    expect(
      tester.getTopLeft(sw).dy,
      lessThan(tester.getTopLeft(find.text('本金（保證金）')).dy),
    );
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(find.text('本金（自動算）'), findsOneWidget);

    Finder fieldWithHint(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
    await tester.enterText(fieldWithHint('例如 12.5'), '12.5');
    await tester.enterText(fieldWithHint('點左邊 + / − 切換賺賠'), '50');
    await tester.pump();
    final margin = tester.widget<TextField>(fieldWithHint('填完 % 跟損益就會算出來'));
    expect(margin.controller!.text, '400');
    expect(find.textContaining('本金＝50 ÷ 12.5%＝'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNotNull,
    );

    // 自己改本金之後，再改 % 不會蓋掉，可以按「用 % 重新算」回來。
    await tester.enterText(fieldWithHint('填完 % 跟損益就會算出來'), '420');
    await tester.pump();
    expect(find.text('本金（保證金）'), findsOneWidget);
    await tester.enterText(fieldWithHint('例如 12.5'), '10');
    await tester.pump();
    expect(margin.controller!.text, '420');
    await tester.tap(find.textContaining('用 % 重新算'));
    await tester.pump();
    expect(margin.controller!.text, '500');
    await finish(tester);
  });

  testWidgets('開倉時間一打開就是直接輸入，打字填日期時間', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // 跟 App 一樣用繁中，日期輸入格式才會跟實機一樣。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
        child: const MaterialApp(
          locale: Locale('zh', 'TW'),
          supportedLocales: [Locale('zh', 'TW'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: CryptoWatchPage(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('開倉時間'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('開倉時間'));
    await tester.pumpAndSettle();

    // 日期：直接是輸入框，不是月曆。
    expect(find.byType(CalendarDatePicker), findsNothing);
    final dateField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    expect(dateField, findsOneWidget);
    await tester.enterText(dateField, '2026/9/3');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    // 時間：直接是時、分兩個輸入框，不是時鐘。
    final timeFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    expect(timeFields, findsNWidgets(2));
    // 24 小時制：直接打 21 就是晚上九點，不用選上午下午。
    expect(find.text('上午'), findsNothing);
    await tester.enterText(timeFields.at(0), '21');
    await tester.enterText(timeFields.at(1), '05');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(find.textContaining('9/3'), findsWidgets);
    expect(find.textContaining('21:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('編輯一單：欄位全換，平倉的可以改回持倉中', () async {
    final repo = TradeRepository(_MemoryStore());
    final t = await repo.add(
      symbol: 'BTC',
      isLong: true,
      leverage: 10,
      margin: 100,
      openedAt: DateTime(2026, 9, 1, 9),
      closedAt: DateTime(2026, 9, 2, 9),
      pnl: 50,
      note: '舊備註',
    );
    final edited = await repo.edit(
      t.id,
      symbol: 'ETH',
      isLong: false,
      leverage: 5,
      margin: 200,
      openedAt: DateTime(2026, 9, 1, 8),
      closedAt: DateTime(2026, 9, 3, 9),
      pnl: -30,
    );
    expect(edited!.id, t.id);
    final saved = (await repo.loadAll()).single;
    expect(saved.symbol, 'ETH');
    expect(saved.isLong, false);
    expect(saved.margin, 200);
    expect(saved.pnl, -30);
    expect(saved.note, isNull);

    await repo.edit(
      t.id,
      symbol: 'ETH',
      isLong: false,
      leverage: 5,
      margin: 200,
      openedAt: DateTime(2026, 9, 1, 8),
    );
    final reopened = (await repo.loadAll()).single;
    expect(reopened.isOpen, true);
    expect(reopened.pnl, isNull);
  });

  testWidgets('已平倉的一單點進去可以編輯，欄位先填好', (tester) async {
    final store = await seeded();
    await pumpPage(tester, const TradeJournalPage(), store);
    await tester.tap(find.textContaining('想追空').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '編輯'));
    await tester.pumpAndSettle();
    expect(find.text('編輯這一單'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    final sign = find.byKey(const ValueKey('pnl-sign'));
    await tester.scrollUntilVisible(
      sign,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('120'), findsOneWidget);
    expect(find.descendant(of: sign, matching: find.text('−')), findsOneWidget);
    await finish(tester);
  });

  test('有紀錄的月份：開倉或平倉的月份＋當月，前後跳過沒紀錄的', () {
    TradeEntry t(DateTime open, [DateTime? close]) => TradeEntry(
      id: '${open.microsecondsSinceEpoch}',
      symbol: 'BTC',
      isLong: true,
      leverage: 10,
      margin: 100,
      openedAt: open,
      closedAt: close,
      pnl: close == null ? null : 1,
    );
    final months = recordMonths([
      t(DateTime(2026, 6, 3), DateTime(2026, 6, 4)),
      t(DateTime(2026, 9, 28), DateTime(2026, 10, 2)),
    ], always: DateTime(2026, 10, 10));
    expect(months, [DateTime(2026, 6), DateTime(2026, 9), DateTime(2026, 10)]);
    expect(prevRecordMonth(months, DateTime(2026, 10)), DateTime(2026, 9));
    expect(prevRecordMonth(months, DateTime(2026, 9)), DateTime(2026, 6));
    expect(prevRecordMonth(months, DateTime(2026, 6)), isNull);
    expect(nextRecordMonth(months, DateTime(2026, 6)), DateTime(2026, 9));
    expect(nextRecordMonth(months, DateTime(2026, 10)), isNull);
  });

  testWidgets('月曆 ‹ 只停在有紀錄的月份，最舊的那個月 ‹ 按不了', (tester) async {
    final store = _MemoryStore();
    final repo = TradeRepository(store);
    final now = DateTime.now();
    final m1 = DateTime(now.year, now.month - 1);
    final m4 = DateTime(now.year, now.month - 4);
    for (final m in [m1, m4]) {
      await repo.add(
        symbol: 'BTC',
        isLong: true,
        leverage: 10,
        margin: 100,
        openedAt: DateTime(m.year, m.month, 5, 9),
        closedAt: DateTime(m.year, m.month, 5, 12),
        pnl: 10,
      );
    }
    await pumpPage(tester, const CryptoWatchPage(), store);
    String title(DateTime m) => '${m.year} 年 ${m.month} 月';
    final back = find.byTooltip('上一個有紀錄的月份');
    final fwd = find.byTooltip('下一個有紀錄的月份');
    IconButton btn(Finder f) => tester.widget<IconButton>(
      find.ancestor(of: f, matching: find.byType(IconButton)).first,
    );

    expect(find.text(title(DateTime(now.year, now.month))), findsOneWidget);
    expect(btn(fwd).onPressed, isNull);
    await tester.tap(back);
    await tester.pump();
    expect(find.text(title(m1)), findsOneWidget);
    await tester.tap(back);
    await tester.pump();
    // 中間沒紀錄的兩個月直接跳過。
    expect(find.text(title(m4)), findsOneWidget);
    expect(btn(back).onPressed, isNull);
    await tester.tap(fwd);
    await tester.pump();
    expect(find.text(title(m1)), findsOneWidget);
    await finish(tester);
  });

  testWidgets('槓桿拉桿最高 18x', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
    expect(find.text('最高 18x'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).max, 18);
    await tester.tap(find.text('18x'));
    await tester.pump();
    expect(find.text('20x'), findsNothing);
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

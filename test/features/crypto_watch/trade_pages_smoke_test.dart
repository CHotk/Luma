import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:lume/features/crypto_watch/trade_ticket_widgets.dart';
import 'package:lume/features/crypto_watch/trade_ui.dart';

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
      // 舊資料有兩位小數，顯示一律四捨五入到小數第一位。
      if (!empty) expect(find.text('+98,645.4'), findsWidgets);
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

  // 2026-10-14 使用者要求：記一筆改成一題一題問，第一題先問是不是補記。
  Future<void> openNewTrade(WidgetTester tester) async {
    await pumpPage(tester, const CryptoWatchPage(), _MemoryStore());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text('記一筆交易'));
    await tester.pumpAndSettle();
  }

  Future<void> tapIn(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  testWidgets('記一筆：一題一題問，答完一題才出下一題，全部答完才能存', (tester) async {
    await openNewTrade(tester);
    expect(find.text('記一筆交易'), findsWidgets);
    expect(find.text('現在開倉'), findsOneWidget);
    expect(find.text('補記以前的單'), findsOneWidget);
    expect(find.text('幣種'), findsNothing);
    FilledButton save() => tester.widget<FilledButton>(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(FilledButton),
          )
          .last,
    );
    expect(save().onPressed, isNull);

    await tapIn(tester, find.text('現在開倉'));
    expect(find.text('記一筆開倉'), findsOneWidget);
    expect(find.text('幣種'), findsOneWidget);
    expect(find.text('方向'), findsNothing);
    await tapIn(tester, find.text('BTC'));
    expect(find.text('方向'), findsOneWidget);
    expect(find.text('槓桿'), findsNothing);
    await tapIn(tester, find.text('多 ▲'));
    expect(find.text('槓桿'), findsOneWidget);
    await tapIn(tester, find.text('用 10x，下一題'));
    // 不是補記：沒有盈虧那題，直接問本金。
    expect(find.text('盈虧 %'), findsNothing);
    expect(find.text('本金（保證金）'), findsOneWidget);
    await tester.enterText(fieldWithHint('例如 400'), '400');
    await tester.pump();
    expect(find.textContaining('4,000 USDT'), findsOneWidget);
    expect(save().onPressed, isNull);
    await tapIn(tester, find.text('下一題'));
    expect(find.text('開倉時間'), findsOneWidget);
    expect(find.text('平倉時間'), findsNothing);
    await tapIn(tester, find.text('時間對了，下一題'));
    expect(find.text('備註（選填）'), findsOneWidget);
    expect(find.text('儲存（持倉中）'), findsOneWidget);
    expect(save().onPressed, isNotNull);
    await finish(tester);
  });

  testWidgets('補記：多一題盈虧，填 % 跟損益自動算本金，時間多平倉', (tester) async {
    await openNewTrade(tester);
    await tapIn(tester, find.text('補記以前的單'));
    expect(find.text('補記一單'), findsOneWidget);
    await tapIn(tester, find.text('ETH'));
    await tapIn(tester, find.text('空 ▼'));
    await tapIn(tester, find.text('用 10x，下一題'));
    expect(find.text('盈虧 %'), findsOneWidget);
    expect(find.text('本金（自動算）'), findsNothing);

    // 賺賠只有一個 +／− 切換，% 跟損益一起變。
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('賺')), findsNothing);
    final sign = find.byKey(const ValueKey('pnl-sign'));
    expect(find.descendant(of: sign, matching: find.text('+')), findsOneWidget);
    await tapIn(tester, sign);
    expect(find.descendant(of: sign, matching: find.text('−')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pct-sign')),
        matching: find.text('−'),
      ),
      findsOneWidget,
    );
    await tapIn(tester, sign);

    await tester.enterText(fieldWithHint('例如 12.5'), '12.5');
    await tester.enterText(fieldWithHint('點左邊 + / − 切換賺賠'), '50');
    await tester.pump();
    await tapIn(tester, find.text('下一題'));
    expect(find.text('本金（自動算）'), findsOneWidget);
    final margin = tester.widget<TextField>(fieldWithHint('填完 % 跟損益就會算出來'));
    expect(margin.controller!.text, '400');
    expect(find.textContaining('本金＝50 ÷ 12.5%＝'), findsOneWidget);

    // 自己改本金之後，再改 % 不會蓋掉，可以按「用 % 重新算」回來。
    await tester.enterText(fieldWithHint('填完 % 跟損益就會算出來'), '420');
    await tester.pump();
    expect(find.text('本金（保證金）'), findsOneWidget);
    await tester.enterText(fieldWithHint('例如 12.5'), '10');
    await tester.pump();
    expect(margin.controller!.text, '420');
    await tapIn(tester, find.textContaining('用 % 重新算'));
    expect(margin.controller!.text, '500');

    await tapIn(tester, find.text('下一題'));
    expect(find.text('開倉時間'), findsOneWidget);
    expect(find.text('平倉時間'), findsOneWidget);
    expect(find.textContaining('持倉'), findsWidgets);
    await tapIn(tester, find.text('時間對了，下一題'));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNotNull,
    );
    await finish(tester);
  });

  testWidgets('日期跟時間同一格打：只打數字，自動補斜線冒號', (tester) async {
    await openNewTrade(tester);
    await tapIn(tester, find.text('現在開倉'));
    await tapIn(tester, find.text('BTC'));
    await tapIn(tester, find.text('多 ▲'));
    await tapIn(tester, find.text('用 10x，下一題'));
    await tester.enterText(fieldWithHint('例如 400'), '400');
    await tester.pump();
    await tapIn(tester, find.text('下一題'));
    await tapIn(tester, find.text('開倉時間'));

    // 只有一個輸入框，不是先日期再時間兩段。
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsNothing);
    await tester.enterText(field, '09032105');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '09/03 21:05');
    await tapIn(tester, find.text('好'));
    expect(find.textContaining('9/3'), findsWidgets);
    expect(find.textContaining('21:05'), findsOneWidget);
    await finish(tester);
  });

  test('日期時間：數字補格式、年份從 20 開頭、不存在的日期不算', () {
    expect(formatDateTimeDigits('10142140'), '10/14 21:40');
    expect(formatDateTimeDigits('1014'), '10/14');
    expect(formatDateTimeDigits('101421409999'), '10/14 21:40');
    expect(formatDateTimeDigits('202510142140'), '2025/10/14 21:40');
    final now = DateTime(2026, 10, 14, 22);
    expect(
      parseTradeDateTime('10/14 21:40', now: now),
      DateTime(2026, 10, 14, 21, 40),
    );
    expect(
      parseTradeDateTime('2025/10/14 21:40', now: now),
      DateTime(2025, 10, 14, 21, 40),
    );
    // 沒寫年份、今年還沒到的日子當去年。
    expect(
      parseTradeDateTime('12/31 10:00', now: now),
      DateTime(2025, 12, 31, 10),
    );
    expect(parseTradeDateTime('02/30 10:00', now: now), isNull);
    expect(parseTradeDateTime('10/14 25:00', now: now), isNull);
    expect(parseTradeDateTime('10/14 21', now: now), isNull);
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

  testWidgets('最上面的損益卡跟著月曆的月份變；月曆標出開倉日、平倉日', (tester) async {
    final store = _MemoryStore();
    final repo = TradeRepository(store);
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    await repo.add(
      symbol: 'BTC',
      isLong: true,
      leverage: 10,
      margin: 100,
      openedAt: DateTime(last.year, last.month, 3, 9),
      closedAt: DateTime(last.year, last.month, 5, 12),
      pnl: 77,
    );
    await repo.add(
      symbol: 'ETH',
      isLong: true,
      leverage: 5,
      margin: 100,
      openedAt: DateTime(now.year, now.month, 1, 9),
      closedAt: DateTime(now.year, now.month, 1, 12),
      pnl: -12,
    );
    await pumpPage(tester, const CryptoWatchPage(), store);
    expect(find.textContaining('${now.month} 月已實現損益'), findsOneWidget);
    expect(find.text('−12'), findsWidgets);
    // 這個月 1 號同一天開又平：開、平兩個標籤都在（另外圖例各一個）。
    expect(find.text('開'), findsNWidgets(2));
    expect(find.text('平'), findsNWidgets(2));

    await tester.tap(find.byTooltip('上一個有紀錄的月份'));
    await tester.pump();
    expect(find.textContaining('${last.month} 月已實現損益'), findsOneWidget);
    expect(find.text('+77'), findsWidgets);
    expect(find.text('−12'), findsNothing);
    // 上個月 3 號開、5 號平：各一個標籤＋圖例。
    expect(find.text('開'), findsNWidgets(2));
    expect(find.text('平'), findsNWidgets(2));
    await finish(tester);
  });

  // 2026-10-12 使用者回報：先平掉一單、晚上又開新的，月曆固定「開」在左
  // 看起來像當天開當天平；點整天抱著單的那天，進去什麼都沒有。
  Future<(_MemoryStore, DateTime)> heldAndSwapped() async {
    final store = _MemoryStore();
    final repo = TradeRepository(store);
    final now = DateTime.now();
    final m = DateTime(now.year, now.month - 1);
    await repo.add(
      symbol: 'BTC',
      isLong: true,
      leverage: 10,
      margin: 100,
      openedAt: DateTime(m.year, m.month, 2, 9),
      closedAt: DateTime(m.year, m.month, 4, 10),
      pnl: 30,
    );
    await repo.add(
      symbol: 'ETH',
      isLong: false,
      leverage: 5,
      margin: 100,
      openedAt: DateTime(m.year, m.month, 4, 22),
    );
    return (store, m);
  }

  testWidgets('同一天先平後開：月曆上「平」排在「開」左邊', (tester) async {
    final (store, _) = await heldAndSwapped();
    await pumpPage(tester, const CryptoWatchPage(), store);
    await tester.tap(find.byTooltip('上一個有紀錄的月份'));
    await tester.pump();
    // 月曆格子裡的標籤在圖例上面，取最上面那個。
    Offset topMost(String text) => tester
        .widgetList(find.text(text))
        .map((w) => tester.getTopLeft(find.byWidget(w)))
        .reduce((a, b) => a.dy < b.dy ? a : b);
    final close = topMost('平'), open = topMost('開');
    // 4 號那格：平在左、開在右（同一列）。2 號那格的「開」在更前面一格，
    // 所以比的是 4 號的開：找跟「平」同一高度、在它右邊的那個「開」。
    final opensOnRow = tester
        .widgetList(find.text('開'))
        .map((w) => tester.getTopLeft(find.byWidget(w)))
        .where((o) => (o.dy - close.dy).abs() < 1 && o.dx > close.dx);
    expect(opensOnRow, isNotEmpty);
    expect(open.dy, lessThanOrEqualTo(close.dy));
    await finish(tester);
  });

  testWidgets('點整天抱著單的那天：列出「這天一直抱著的單」', (tester) async {
    final (store, m) = await heldAndSwapped();
    await pumpPage(
      tester,
      TradeDayPage(day: DateTime(m.year, m.month, 3)),
      store,
    );
    expect(find.text('這天一直抱著的單'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.textContaining('抱著 1 單'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('票根：甘特圖點已平倉的單出票根（可收起）；持倉中是亮卡＋平倉鈕', (tester) async {
    await pumpPage(tester, const CryptoWatchPage(), await seeded());
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    // 持倉中：亮卡上有實心「平倉」。
    expect(find.widgetWithText(FilledButton, '平倉'), findsOneWidget);
    expect(find.text('已平倉的紀錄・只是看', findRichText: true), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    final btc = find.textContaining('BTC空', findRichText: true);
    await tester.ensureVisible(btc);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(btc);
    await tester.pump();
    expect(find.textContaining('已平倉的紀錄・只是看'), findsOneWidget);
    // 票根裡是點到的那一單（BTC −120、筆記）。
    Finder inReceipt(String text) => find.descendant(
      of: find.byType(TradeReceipt),
      matching: find.text(text, skipOffstage: false),
      skipOffstage: false,
    );
    expect(inReceipt(fmtPnl(-120)), findsOneWidget);
    expect(inReceipt('想追空，結果被軋'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.textContaining('已平倉的紀錄・只是看'), findsNothing);
    // 點持倉中的那條：不出票根，指去下面的亮卡。
    final eth = find.textContaining('ETH多', findRichText: true);
    await tester.ensureVisible(eth);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(eth);
    await tester.pump();
    expect(find.textContaining('這單還抱著', skipOffstage: false), findsOneWidget);
    await finish(tester);
  });

  test('交易數字最多小數第一位，超過四捨五入', () {
    expect(round1(12.36), 12.4);
    expect(round1(12.34), 12.3);
    expect(fmtAmount(1234.56), '1,234.6');
    expect(fmtPnl(-0.04), '0');
    expect(fmtPnl(98765.43), '+98,765.4');
    expect(fmtAmount(400), '400');
  });

  testWidgets('輸入框打到小數第二位自動四捨五入；本金自動算也只到第一位', (tester) async {
    await openNewTrade(tester);
    await tapIn(tester, find.text('補記以前的單'));
    await tapIn(tester, find.text('BTC'));
    await tapIn(tester, find.text('多 ▲'));
    await tapIn(tester, find.text('用 10x，下一題'));
    TextField field(String hint) =>
        tester.widget<TextField>(fieldWithHint(hint));

    // 盈虧 % 打 12.36 → 變 12.4。
    await tester.enterText(fieldWithHint('例如 12.5'), '12.36');
    await tester.pump();
    expect(field('例如 12.5').controller!.text, '12.4');

    // 損益 50 ÷ 12.4% ＝ 403.2258… → 本金 403.2。
    await tester.enterText(fieldWithHint('點左邊 + / − 切換賺賠'), '50');
    await tester.pump();
    await tapIn(tester, find.text('下一題'));
    expect(field('填完 % 跟損益就會算出來').controller!.text, '403.2');
    await finish(tester);
  });

  testWidgets('槓桿拉桿最高 18x', (tester) async {
    await openNewTrade(tester);
    await tapIn(tester, find.text('現在開倉'));
    await tapIn(tester, find.text('BTC'));
    await tapIn(tester, find.text('多 ▲'));
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
    // 月初資金在最上面的損益卡裡點（月曆上那排小格子跟它重複，拿掉了）。
    await tester.tap(find.textContaining('設定月初資金'));
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
    expect(find.textContaining('月初 2,000 USDT'), findsOneWidget);
    expect(find.textContaining('已設定'), findsOneWidget);
    expect(find.textContaining('設定月初資金'), findsNothing);
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

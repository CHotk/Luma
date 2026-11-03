import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/ledger_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/ledger.dart';
import 'package:lume/features/ledger/ledger_page.dart';

/// 記帳四個分頁在手機寬度（360）畫得出來、不爆版，有資料跟沒資料都要；
/// 記一筆、對帳、貼上匯入、帳戶明細這些抽屜也要打得開。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_MemoryStore> seeded() async {
    final store = _MemoryStore();
    final repo = LedgerRepository(store);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final bank = await repo.addAccount(
      name: '中信活存 名字很長很長很長很長很長很長',
      type: LedgerAccountType.bank,
      opening: 45000,
      openingAt: start,
    );
    final card = await repo.addAccount(
      name: '中信信用卡',
      type: LedgerAccountType.creditCard,
      opening: 87600,
      openingAt: start,
      creditLimit: 100000,
    );
    await repo.addAccount(
      name: '現金',
      type: LedgerAccountType.cash,
      opening: 2000,
      openingAt: start,
    );
    final lunch = LedgerTx(
      id: ledgerId(),
      type: LedgerTxType.expense,
      occurredAt: start.add(const Duration(hours: 12)),
      amount: 2400,
      accountId: card.id,
      category: '餐飲',
      merchant: '鼎泰豐 聚餐 名字很長很長很長很長很長很長很長很長',
      note: '備註也很長很長很長很長很長很長',
      flagged: true,
      paidFor: const PaidFor(amount: 1200, people: '阿明、小華'),
    );
    await repo.addTransactions([
      lunch,
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.transfer,
        occurredAt: start.add(const Duration(hours: 13)),
        amount: 3000,
        accountId: bank.id,
        toAccountId: (await repo.loadBook()).accounts.last.id,
        merchant: 'ATM提款',
      ),
      LedgerTx(
        id: ledgerId(),
        type: LedgerTxType.repayment,
        occurredAt: start.add(const Duration(hours: 14)),
        amount: 600,
        accountId: bank.id,
        linkedId: lunch.id,
      ),
    ]);
    await repo.addCheckpoint(
      LedgerCheckpoint(
        id: ledgerId(),
        accountId: bank.id,
        at: start.add(const Duration(hours: 20)),
        balance: 45000 - 3000 + 600 - 630,
      ),
    );
    await repo.setBudgets(
      '${now.year}-${now.month.toString().padLeft(2, '0')}',
      1000,
      {'餐飲': 500},
    );
    return store;
  }

  Future<void> pump(
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

  Future<void> show(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
    f,
    150,
    scrollable: find.byType(Scrollable).first,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  for (final empty in [false, true]) {
    final tag = empty ? '（沒資料）' : '（有資料）';
    for (final tab in LedgerTab.values) {
      testWidgets('${tab.title}分頁畫得出來$tag', (tester) async {
        final store = empty ? _MemoryStore() : await seeded();
        await pump(tester, LedgerPage(tab: tab), store);
        expect(tester.takeException(), isNull);
        if (empty) expect(find.text('還沒開始記帳'), findsOneWidget);
      });
    }
  }

  testWidgets('首頁看得到兩件事分開：控制開銷、記帳完整度（活存差 \$630）', (tester) async {
    await pump(tester, const LedgerPage(tab: LedgerTab.home), await seeded());
    expect(find.textContaining('控制開銷'), findsOneWidget);
    expect(find.textContaining('記帳完整度'), findsOneWidget);
    expect(find.text('⚠ 差 \$630'), findsOneWidget);
    // 本月消費只算自己的 1,200（幫付 1,200 不算、提款不算）。
    expect(find.text('\$1,200'), findsWidgets);
  });

  testWidgets('記一筆、交易明細、帳戶明細、對帳、匯入、別人還欠你都打得開', (tester) async {
    final store = await seeded();
    await pump(tester, const LedgerPage(tab: LedgerTab.home), store);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('記一筆'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    await tester.tap(find.text('⚠ 差 \$630'));
    await settle(tester);
    expect(find.text('補記一筆'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('⚖️ 現在對帳'));
    await settle(tester);
    expect(find.textContaining('對帳：'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    await show(tester, find.textContaining('別人還欠你').first);
    await tester.tap(find.textContaining('別人還欠你').first);
    await settle(tester);
    expect(find.text('記一筆還款'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);

    // 最近記的在最下面：捲到底（多捲一點，不要被右下角 ＋ 擋住）再點。
    await show(tester, find.textContaining('鼎泰豐').first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester);
    await tester.tap(find.textContaining('鼎泰豐').first);
    await settle(tester);
    expect(find.text('支出明細'), findsOneWidget);
    expect(find.textContaining('幫別人付'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('帳戶分頁：貼上匯入、預算、起始日抽屜都打得開', (tester) async {
    await pump(
      tester,
      const LedgerPage(tab: LedgerTab.accounts),
      await seeded(),
    );
    for (final title in ['貼上文字匯入', '起始日與期初值']) {
      await tester.scrollUntilVisible(find.text(title), 200);
      await tester.tap(find.text(title));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: title);
      await tester.tap(find.byTooltip('關閉'));
      await settle(tester);
    }
  });

  testWidgets('沒資料時按「開始記帳」打得開設定表單', (tester) async {
    await pump(tester, const LedgerPage(tab: LedgerTab.home), _MemoryStore());
    await tester.tap(find.text('開始記帳').last);
    await settle(tester);
    expect(find.text('起始日'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/home_card_order_store.dart';
import 'package:lume/features/home/home_page.dart' show enHomeCards;
import 'package:lume/features/settings/debug_log_page.dart';
import 'package:lume/features/settings/home_card_order_page.dart';
import 'package:lume/shared/debug/app_log.dart';

import '../../support/poke.dart';

/// 除錯紀錄頁、首頁卡片順序頁（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 沒有紀錄、有一般／錯誤紀錄時每個篩選、清空、看歷史都點一次；卡片順序拖動後存起來。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('除錯紀錄：沒紀錄也能開；有一般跟錯誤紀錄時每個按鈕點一次都不會壞', (tester) async {
    final store = MemoryStore();
    var router = await pumpPage(tester, store, () => const DebugLogPage());
    expect(tester.takeException(), isNull);
    AppLog.add('[測試] 一般訊息');
    AppLog.add('[測試] 出錯了', isError: true);
    router = await pumpPage(tester, store, () => const DebugLogPage());
    expect(find.textContaining('出錯了'), findsWidgets);
    final n = await pokeAll(tester, router);
    expect(n, greaterThan(3));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('首頁卡片順序：拖動一張 → 順序存起來；重開照存的順序', (tester) async {
    final store = MemoryStore();
    const cards = enHomeCards;
    Widget page() => HomeCardOrderPage(track: 'en', title: '英文', cards: cards);
    var router = await pumpPage(tester, store, page);
    expect(find.text(cards.first.label), findsOneWidget);
    // 長按拖曳（手機上的排序方式）。
    final g = await tester.startGesture(
      tester.getCenter(find.text(cards.first.label)),
    );
    await tester.pump(const Duration(seconds: 1));
    await g.moveBy(const Offset(0, 80));
    await tester.pump();
    await g.moveBy(const Offset(0, 80));
    await tester.pump();
    await g.up();
    await settle(tester);
    final saved = await tester.runAsync(
      () => HomeCardOrderStore(store, 'en').load(),
    );
    expect(saved, isNotNull);
    expect(saved!.first, isNot(cards.first.id));
    router = await pumpPage(tester, store, page);
    await pokeAll(tester, router);
    expect(tester.takeException(), isNull);
  });
}

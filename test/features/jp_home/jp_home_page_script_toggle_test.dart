import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/jp_home/jp_home_page.dart';
import 'package:lume/shared/widgets/sakura_petals.dart';

void main() {
  // 櫻花特效是連續動畫，會讓 pumpAndSettle 永遠等不完。
  sakuraPetalsEnabled = false;
  // 兩個情境放同一個 testWidgets、共用一次 pumpWidget，不要拆成兩個
  // 各自 pumpWidget 的 test——曾經拆過，兩個各自都能單獨跑過，但
  // 兩個放同一個檔案接連跑，第二個的第一次 pumpAndSettle 就會卡死
  // 逾時（Riverpod FutureProvider.autoDispose 跨 test 的釋放時機跟
  // flutter_test 的 binding reset 對不上，屬於測試環境本身的已知
  // 眉角，不是畫面邏輯的問題）。同一個 pumpWidget 裡順著操作下去就
  // 不會踩到。
  testWidgets('日文首頁預覽卡片切平／片假名：字要跟著換，選到哪一個不能跑掉', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
        child: const MaterialApp(home: JpHomePage()),
      ),
    );
    await tester.pumpAndSettle();

    // 一開始是平假名，放大預覽應該顯示「あ」。
    expect(find.text('あ'), findsWidgets);
    expect(find.text('ア'), findsNothing);

    await tester.tap(find.text('片'));
    await tester.pumpAndSettle();

    // 切到片假名之後，預覽（不管是格子還是放大那塊）應該出現「ア」，
    // 「あ」不該再出現──如果還在，代表切換沒真的生效。
    expect(find.text('ア'), findsWidgets);
    expect(find.text('あ'), findsNothing);

    await tester.tap(find.text('平'));
    await tester.pumpAndSettle();

    // 換到「か行」，選第二個字「き」。
    await tester.tap(find.text('か行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('片'));
    await tester.pumpAndSettle();

    // 切成片假名之後應該還在「か行」第二個字（片假名是「キ」），
    // 不能跳回「あ行」第一個字——如果跳回去了，畫面會變成顯示「ア」
    // 而不是「キ」，「き」也不該再出現（已經整個切成片假名）。
    expect(find.text('キ'), findsWidgets);
    expect(find.text('ア'), findsNothing);
    expect(find.text('き'), findsNothing);

    // 行的顯示字也要跟著換——片假名模式選到的那一行要顯示「カ行」，
    // 不是固定顯示平假名的「か行」（2026-09-18 使用者回饋）。
    expect(find.text('カ行'), findsOneWidget);
    expect(find.text('か行'), findsNothing);
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

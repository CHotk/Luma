import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/i88_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/i88/i88_log_page.dart';

/// i88 操作紀錄：每個動作自動記一筆、寫了改了什麼、只增不刪；頁面可搜尋、沒有刪除鈕。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('新增、編輯、刪除、改目標都各記一筆，編輯寫出改了哪些欄位', () async {
    final repo = I88Repository(_MemoryStore());
    final e = await repo.add(
      at: DateTime(2026, 11, 5, 21),
      amount: 500,
      note: '晚上',
    );
    await repo.update(e.copyWith(amount: -300, note: ''));
    await repo.delete(e.id);
    await repo.setTarget(30000);
    await repo.setTarget(40000);
    final log = await repo.loadLog();
    expect(log.map((x) => x.action).toSet(), {'新增', '編輯', '刪除', '改目標'});
    expect(log.length, 5);
    final edit = log.firstWhere((x) => x.action == '編輯');
    expect(edit.detail, contains('金額：贏 \$500 → 輸 \$300'));
    expect(edit.detail, contains('備註：晚上 → （空）'));
    final target = log.where((x) => x.action == '改目標').toList();
    expect(target.any((x) => x.detail == '\$30000 → \$40000'), isTrue);
    // 刪除之後紀錄還在（只增不刪）。
    expect(log.any((x) => x.action == '新增' && x.refId == e.id), isTrue);
  });

  testWidgets('操作紀錄頁：列出每一筆、可搜尋、沒有刪除鈕', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    final repo = I88Repository(store);
    await tester.runAsync(() async {
      final e = await repo.add(at: DateTime(2026, 11, 5, 21), amount: 800);
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await repo.delete(e.id);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: I88LogPage()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.textContaining('共 2 筆'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('刪除'), findsOneWidget);
    expect(find.textContaining('只增不刪'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在的字');
    await tester.pump();
    expect(find.text('沒有符合的紀錄'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '贏 800');
    await tester.pump();
    expect(find.textContaining('符合 2 筆'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
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

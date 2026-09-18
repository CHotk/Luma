import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/jp_home/jp_home_page.dart';

void main() {
  testWidgets('日文首頁預覽卡片切平／片假名，預覽字要跟著換', (tester) async {
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

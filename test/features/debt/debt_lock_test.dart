import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/diary_password_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/debt/debt_lock.dart';
import 'package:lume/features/settings/other_settings_page.dart';

/// 負債管理要密碼才能開，密碼跟日記同一組（改日記密碼，負債也跟著變）。
void main() {
  Future<void> pump(WidgetTester tester, _MemoryStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          home: DebtLockGate(title: '負債管理', child: Text('裡面的內容')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('預設密碼跟日記一樣，打錯不給進', (tester) async {
    await pump(tester, _MemoryStore());
    expect(find.text('裡面的內容'), findsNothing);
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('解鎖'));
    await tester.pump();
    expect(find.text('密碼錯誤'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      DiaryPasswordStore.defaultPassword,
    );
    await tester.tap(find.text('解鎖'));
    await tester.pump();
    expect(find.text('裡面的內容'), findsOneWidget);
  });

  testWidgets('在日記改了密碼，負債也要用新的', (tester) async {
    final store = _MemoryStore();
    await DiaryPasswordStore(store).savePassword('2468');
    await pump(tester, store);
    await tester.enterText(
      find.byType(TextField),
      DiaryPasswordStore.defaultPassword,
    );
    await tester.tap(find.text('解鎖'));
    await tester.pump();
    expect(find.text('裡面的內容'), findsNothing);
    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('解鎖'));
    await tester.pump();
    expect(find.text('裡面的內容'), findsOneWidget);
  });

  testWidgets('負債管理的齒輪設定可以改密碼，改的是日記同一組', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          home: OtherSettingsPage(fromLocation: '/debt'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('負債管理'), findsOneWidget);
    expect(find.text('日記／負債密碼'), findsOneWidget);
    await tester.tap(find.text('變更'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1357');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(await DiaryPasswordStore(store).loadPassword(), '1357');
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

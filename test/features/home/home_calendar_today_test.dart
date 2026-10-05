import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/history.dart';
import 'package:lume/features/home/home_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('英文首頁還開著（測驗疊在上面）時答一題，月曆要重算出今天有練', () async {
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
    );
    addTearDown(container.dispose);
    final now = DateTime.now();

    // 首頁先開著（listen 住，不會被 autoDispose 掉），跟真實情況一樣。
    final sub = container.listen(homeStateProvider, (_, _) {});
    addTearDown(sub.close);
    final before = await container.read(homeStateProvider.future);

    await container
        .read(historyRepositoryProvider)
        .appendAnswer(
          HistoryEntry(word: 'zzz-test-word', correct: true, at: now),
          stealth: false,
        );
    // 測驗頁每答一題就做這一步（quiz_controller.dart）。
    container.read(dataRevisionProvider.notifier).state++;
    final after = await container.read(homeStateProvider.future);

    expect(after.practicedDaysThisMonth, contains(now.day));
    expect(
      after.allPracticedDates,
      contains(DateTime(now.year, now.month, now.day)),
    );
    expect(identical(before, after), isFalse);
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

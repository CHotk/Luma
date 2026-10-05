import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/features/jp_home/jp_home_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('只考了試沒練習的日子，月曆也要算練過，點進去看得到考了幾題', () async {
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
    );
    addTearDown(container.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await container
        .read(kanaExamRepositoryProvider)
        .add(
          KanaExamEntry(
            id: 'e1',
            roundId: 'r1',
            kana: 'あ',
            romaji: 'a',
            isCorrect: true,
            examType: 'kana',
            savedAt: now,
            strokes: const [],
          ),
        );

    final sub = container.listen(jpHomeStateProvider, (_, _) {});
    addTearDown(sub.close);
    final state = await container.read(jpHomeStateProvider.future);

    expect(state.practicedDaysThisMonth, contains(now.day));
    expect(state.streakDays, 1);
    expect(state.daySummaries[today]!.examCount, 1);
    expect(state.daySummaries[today]!.examCorrect, 1);
    expect(state.daySummaries[today]!.count, 0);
    // 首頁進度環：考試題數也算今天練了幾題。
    expect(state.todayCount, 1);
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

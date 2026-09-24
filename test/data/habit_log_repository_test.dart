import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/habit_log_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/habit_config.dart';

void main() {
  test('看盤／抽菸／喝酒各存各的 key，互不影響', () async {
    final store = _MemoryStore();
    final crypto = HabitLogRepository(store, cryptoWatchHabit.storageKey);
    final smoking = HabitLogRepository(store, smokingHabit.storageKey);
    await crypto.add(reason: '焦慮');
    await crypto.add();
    await smoking.add(reason: '壓力');

    expect((await crypto.loadAll()).length, 2);
    expect((await smoking.loadAll()).length, 1);
    expect(
      {for (final h in allHabits) h.storageKey}.length,
      allHabits.length,
      reason: '儲存 key 不能重複',
    );
  });

  test('刪除是墓碑：畫面看不到，但同步用的清單還在', () async {
    final repo = HabitLogRepository(_MemoryStore(), drinkingHabit.storageKey);
    final e = await repo.add();
    await repo.delete(e.id);
    expect(await repo.loadAll(), isEmpty);
    final raw = await repo.allForUpload();
    expect(raw.single.deletedAt, isNotNull);
  });

  test('雲端內容跟本機一樣時 mergeFromCloud 異動數是 0', () async {
    final repo = HabitLogRepository(_MemoryStore(), smokingHabit.storageKey);
    await repo.add();
    expect(await repo.mergeFromCloud(await repo.allForUpload()), 0);
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

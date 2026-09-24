import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/crypto_watch_repository.dart';
import 'package:lume/data/repositories/drinking_repository.dart';
import 'package:lume/data/repositories/smoking_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';

void main() {
  test('看盤／抽菸／喝酒各自一份資料，互不影響', () async {
    final store = _MemoryStore();
    final crypto = CryptoWatchRepository(store);
    final smoking = SmokingRepository(store);
    final drinking = DrinkingRepository(store);
    await crypto.add(reason: '焦慮');
    await crypto.add();
    await smoking.add(reason: '壓力');

    expect((await crypto.loadAll()).length, 2);
    expect((await smoking.loadAll()).length, 1);
    expect(await drinking.loadAll(), isEmpty);
  });

  test('刪除是墓碑：畫面看不到，但同步用的清單還在', () async {
    final repo = DrinkingRepository(_MemoryStore());
    final e = await repo.add();
    await repo.delete(e.id);
    expect(await repo.loadAll(), isEmpty);
    expect((await repo.allForUpload()).single.deletedAt, isNotNull);
  });

  test('雲端內容跟本機一樣時 mergeFromCloud 異動數是 0', () async {
    final repo = SmokingRepository(_MemoryStore());
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

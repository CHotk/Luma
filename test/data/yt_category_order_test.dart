import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';

void main() {
  test('「看過但不喜歡」不管什麼時候加，列表裡都固定排最後', () async {
    final repo = YtTrackerRepository(_MemoryStore());
    await repo.addCategory(
      const YtCategory(id: 'a', name: 'A', colorValue: 0xFF000000),
    );
    await repo.addCategory(
      const YtCategory(
        id: ytDislikedCategoryId,
        name: '看過但不喜歡',
        colorValue: 0xFF000000,
      ),
    );
    await repo.addCategory(
      const YtCategory(id: 'b', name: 'B', colorValue: 0xFF000000),
    );
    final ids = (await repo.loadCategories()).map((c) => c.id).toList();
    expect(ids, ['a', 'b', ytDislikedCategoryId]);
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

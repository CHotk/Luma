import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/kana_practice_repository.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/kana_practice.dart';

void main() {
  late _MemoryStore store;
  late KanaPracticeRepository repo;

  setUp(() {
    store = _MemoryStore();
    repo = KanaPracticeRepository(store);
  });

  KanaPracticeEntry entry(String id, {String kana = 'あ'}) => KanaPracticeEntry(
    id: id,
    kana: kana,
    romaji: 'a',
    assisted: true,
    savedAt: DateTime(2026, 9, 18),
    strokes: const [
      [(0.1, 0.2, 0), (0.3, 0.4, 120)],
    ],
  );

  test('upsert：同一個 id 是換掉整筆，不是加一筆', () async {
    await repo.upsert(entry('a1'));
    await repo.upsert(entry('a1', kana: 'い'));

    final all = await repo.loadAll();
    expect(all.length, 1);
    expect(all.single.kana, 'い');
  });

  test('upsert：不同 id 各自成一筆', () async {
    await repo.upsert(entry('a1'));
    await repo.upsert(entry('a2'));

    expect((await repo.loadAll()).length, 2);
  });

  test('delete：把那筆連同已經存過的幾版一起丟掉', () async {
    await repo.upsert(entry('a1'));
    await repo.upsert(entry('a2'));
    await repo.delete('a1');

    final all = await repo.loadAll();
    expect(all.length, 1);
    expect(all.single.id, 'a2');
  });

  test('exportJson：筆數對得上，JSON 內容可以還原回同樣的紀錄', () async {
    await repo.upsert(entry('a1'));
    await repo.upsert(entry('a2', kana: 'か'));

    final result = await repo.exportJson();
    expect(result.count, 2);

    final decoded = (jsonDecode(result.text) as List)
        .cast<Map<String, dynamic>>()
        .map(KanaPracticeEntry.fromJson)
        .toList();
    expect(decoded.map((e) => e.id).toSet(), {'a1', 'a2'});
    expect(
      decoded.firstWhere((e) => e.id == 'a1').strokes.first.first.$1,
      0.1,
    );
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

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

  test('mergeFromCloud：雲端內容跟本機一樣（含巢狀筆畫）時異動數是 0', () async {
    await repo.upsert(entry('a1'));
    await repo.upsert(entry('a2'));
    final cloud = [
      for (final e in await repo.allForUpload())
        KanaPracticeEntry.fromJson(
          jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
        ),
    ];
    expect(await repo.mergeFromCloud(cloud), 0);
  });

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
    expect(decoded.firstWhere((e) => e.id == 'a1').strokes.first.first.$1, 0.1);
  });

  test('mergeSeed：種子跟本機同一個 id，用種子那份蓋掉本機的舊版本', () async {
    await repo.upsert(entry('a1', kana: '本機舊版'));
    await repo.upsert(entry('a2'));

    await repo.mergeSeed([entry('a1', kana: '種子新版')]);

    final all = await repo.loadAll();
    expect(all.length, 2, reason: 'a2 本機沒對到種子，要留著');
    expect(all.firstWhere((e) => e.id == 'a1').kana, '種子新版');
  });

  test('mergeSeed：種子有本機沒有的 id，直接加進去', () async {
    await repo.upsert(entry('a1'));

    await repo.mergeSeed([entry('seed-only')]);

    final ids = (await repo.loadAll()).map((e) => e.id).toSet();
    expect(ids, {'a1', 'seed-only'});
  });

  test('mergeSeed：種子是空的就什麼都不動', () async {
    await repo.upsert(entry('a1'));

    await repo.mergeSeed(const []);

    expect((await repo.loadAll()).length, 1);
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

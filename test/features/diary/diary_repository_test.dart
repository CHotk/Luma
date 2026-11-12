import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/diary_repository.dart';
import 'package:lume/domain/models/diary_entry.dart';

import '../../support/poke.dart';

/// 日記資料的邊界（2026-11-12 補到 95%）：快照合併（快照贏、空的不動）、雲端合併
/// （本機贏、刪除永遠贏、回傳異動筆數、空的回 0）、上傳含刪除的、匯出不含刪除的、
/// 刪除／編輯找不到 id 不動。
void main() {
  final t = DateTime(2026, 10, 1);
  DiaryEntry e(String id, String text, {DateTime? at, DateTime? deleted}) =>
      DiaryEntry(
        id: id,
        mood: '🙂',
        text: text,
        savedAt: at ?? t,
        deletedAt: deleted,
      );

  test('快照合併：同 id 換成快照的、快照沒有的留著；空的快照不動', () async {
    final repo = DiaryRepository(MemoryStore());
    await repo.add(e('a', '本機的'));
    await repo.add(e('b', '只有本機'));
    await repo.mergeSeed(const []);
    await repo.mergeSeed([
      e('a', '快照的', at: t.add(const Duration(days: 1))),
      e('c', '快照才有'),
    ]);
    final all = await repo.loadAll();
    expect(all.firstWhere((x) => x.id == 'a').text, '快照的');
    expect(all.map((x) => x.id), containsAll(['a', 'b', 'c']));
  });

  test('雲端合併：本機贏、補新的、刪除永遠贏，回傳異動幾筆；空的回 0', () async {
    final repo = DiaryRepository(MemoryStore());
    await repo.add(e('a', '本機'));
    await repo.add(e('b', '會被雲端刪'));
    expect(await repo.mergeFromCloud(const []), 0);
    final n = await repo.mergeFromCloud([
      e('a', '雲端舊的'),
      e('b', '會被雲端刪', deleted: t),
      e('c', '雲端新的'),
    ]);
    expect(n, 2);
    final all = await repo.loadAll();
    expect(all.firstWhere((x) => x.id == 'a').text, '本機');
    expect(all.any((x) => x.id == 'b'), isFalse);
    expect((await repo.allForUpload()).any((x) => x.id == 'b'), isTrue);
    expect(
      (await repo.loadAllIncludingDeleted()).length,
      (await repo.allForUpload()).length,
    );
  });

  test('匯出不含刪掉的；刪除、編輯找不到 id 不動', () async {
    final repo = DiaryRepository(MemoryStore());
    await repo.add(e('a', '留著'));
    await repo.add(e('b', '刪掉'));
    await repo.delete('b');
    await repo.delete('沒有');
    await repo.update(e('沒有', 'x'));
    await repo.update(e('a', '改過'));
    final out = await repo.exportJson();
    expect(out.count, 1);
    expect(out.text, contains('改過'));
    expect(out.text, isNot(contains('刪掉')));
  });

  test('異動筆數：一樣的不算、新的跟改過的各算一次', () {
    final before = [e('a', '1'), e('b', '2')];
    expect(diaryDiffCount(before, before), 0);
    expect(diaryDiffCount(before, [e('a', '1'), e('b', '改'), e('c', '新')]), 2);
  });
}

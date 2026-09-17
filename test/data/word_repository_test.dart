import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/history_repository.dart';
import 'package:lume/data/repositories/word_repository.dart';
import 'package:lume/data/seed/seed_source.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/history.dart';
import 'package:lume/domain/models/word.dart';

/// 資料同步是最容易寫錯又最難發現的地方：
/// 寫錯就是把成績弄丟，而且要等練兩個月才會發現。
/// 所以這幾個測試比畫面重要得多。
void main() {
  late _MemoryStore store;

  setUp(() => store = _MemoryStore());

  Word word(String w, {int id = 1}) =>
      Word(id: id, word: w, pos: 'n.', zh: '測試', grade: WordGrade.elementary);

  HistoryEntry log(
    String w, {
    required bool ok,
    required int day,
  }) => HistoryEntry(
    word: w,
    correct: ok,
    at: DateTime(2026, 9, day),
  );

  ({WordRepository words, HistoryRepository history}) build(_FakeSeed seed) {
    final history = HistoryRepository(store, seed: seed);
    return (
      words: WordRepository(store: store, history: history, seed: seed),
      history: history,
    );
  }

  test('第一次開啟會匯入打包資料並記下版本', () async {
    final repo = build(
      _FakeSeed(version: 1, words: [word('rain'), word('busy', id: 2)]),
    );

    expect((await repo.words.loadAll()).length, 2);
    expect(store.data['bundle.version.v1'], '1');
  });

  test('版本沒變就不動資料', () async {
    final seed = _FakeSeed(version: 1, words: [word('rain')]);
    await build(seed).words.loadAll();
    seed.bundleCalls = 0;

    await build(seed).words.loadAll();

    expect(seed.bundleCalls, 0, reason: '版本一樣就不該再去讀打包資料');
  });

  test('版本變新時補上新字，本機獨有的字保留', () async {
    await build(
      _FakeSeed(version: 1, words: [word('rain'), word('lonely', id: 2)]),
    ).words.loadAll();

    final all = await build(
      _FakeSeed(version: 2, words: [word('rain'), word('weather', id: 3)]),
    ).words.loadAll();

    expect(all.any((w) => w.word == 'weather'), isTrue, reason: '新字沒補進來');
    expect(all.any((w) => w.word == 'lonely'), isTrue, reason: '本機獨有的字被刪掉了');
  });

  test('對錯次數是從紀錄加總出來的', () async {
    final repo = build(
      _FakeSeed(
        version: 1,
        words: [word('rain')],
        history: [
          log('rain', ok: true, day: 1),
          log('rain', ok: true, day: 2),
          log('rain', ok: false, day: 3),
        ],
      ),
    );

    final rain = (await repo.words.loadAll()).first;

    expect(rain.right, 2);
    expect(rain.wrong, 1);
    expect(rain.lastTest, DateTime(2026, 9, 3), reason: '最後受測日期要取最新的');
  });

  test('去重看內容不是編號：日期不同的紀錄不會被誤判成重複', () async {
    // App 自己先記了一筆。
    final first = build(
      _FakeSeed(
        version: 1,
        words: [word('rain')],
        history: [log('rain', ok: true, day: 1)],
      ),
    );
    await first.history.entries();

    // 對話那邊追加了一筆，字相同但日期（at）不同，不該被當成同一筆。
    final merged = build(
      _FakeSeed(
        version: 2,
        words: [word('rain')],
        history: [
          log('rain', ok: true, day: 1),
          log('rain', ok: false, day: 5),
        ],
      ),
    );
    final entries = await merged.history.entries();

    expect(entries.length, 2, reason: '內容不同的紀錄被當成重複吃掉了');
    final rain = (await merged.words.loadAll()).first;
    expect(rain.right, 1);
    expect(rain.wrong, 1);
  });

  test('同一筆紀錄重複合併不會被算兩次', () async {
    final shared = [log('rain', ok: true, day: 1)];
    await build(
      _FakeSeed(version: 1, words: [word('rain')], history: shared),
    ).history.entries();

    final again = build(
      _FakeSeed(version: 2, words: [word('rain')], history: shared),
    );

    expect((await again.history.entries()).length, 1);
    expect((await again.words.loadAll()).first.right, 1);
  });
}

/// 記憶體版儲存。測試不該碰到真的 SharedPreferences。
class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// 假的打包資料。版本與內容都由測試指定。
class _FakeSeed implements SeedSource {
  _FakeSeed({
    required int version,
    required this.words,
    this.history = const [],
  }) : _version = version;

  final int _version;
  final List<Word> words;
  final List<HistoryEntry> history;
  int bundleCalls = 0;

  @override
  int get bundleVersion => _version;

  @override
  Future<List<Word>> bundle() async {
    bundleCalls++;
    return words;
  }

  @override
  Future<List<HistoryEntry>> bundleHistory() async => history;
}

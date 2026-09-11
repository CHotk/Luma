import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/word_repository.dart';
import 'package:lume/data/seed/seed_source.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/word.dart';

/// 題庫升級是最容易寫錯又最難發現的地方：
/// 寫錯就是把使用者的成績洗掉，而且要等他練兩個月才會發現。
/// 所以這幾個測試比畫面重要得多。
void main() {
  late _MemoryStore store;

  setUp(() => store = _MemoryStore());

  Word word(String w, {int id = 1, int right = 0, int wrong = 0}) => Word(
    id: id,
    word: w,
    pos: 'n.',
    zh: '測試',
    level: WordLevel.elementary,
    right: right,
    wrong: wrong,
  );

  test('第一次開啟會匯入題庫並記下版本', () async {
    final repo = WordRepository(
      store: store,
      seed: _FakeSeed(version: 1, words: [word('rain'), word('busy', id: 2)]),
    );

    final all = await repo.loadAll();

    expect(all.length, 2);
    expect(store.data['seed.version.v1'], '1');
  });

  test('題庫出新版時只補新字，既有成績一個都不動', () async {
    // 先用第一版匯入，並且假裝 rain 已經答對兩次。
    final first = WordRepository(
      store: store,
      seed: _FakeSeed(version: 1, words: [word('rain')]),
    );
    await first.loadAll();
    store.data['words.v1'] = store.data['words.v1']!.replaceAll(
      '"right":0',
      '"right":2',
    );

    // 換成第二版題庫，多了一個字。
    final second = WordRepository(
      store: store,
      seed: _FakeSeed(
        version: 2,
        words: [word('rain'), word('weather', id: 2)],
      ),
    );
    final all = await second.loadAll();

    expect(all.length, 2);
    expect(all.firstWhere((w) => w.word == 'rain').right, 2, reason: '成績被洗掉了');
    expect(all.any((w) => w.word == 'weather'), isTrue, reason: '新字沒補進來');
    expect(store.data['seed.version.v1'], '2');
  });

  test('版本沒變就不動資料', () async {
    final seed = _FakeSeed(version: 1, words: [word('rain')]);
    await WordRepository(store: store, seed: seed).loadAll();
    seed.seedCalls = 0;

    await WordRepository(store: store, seed: seed).loadAll();

    expect(seed.seedCalls, 0, reason: '版本一樣就不該再去讀題庫');
  });

  test('新字的編號接在既有最大號之後，不會撞號', () async {
    await WordRepository(
      store: store,
      seed: _FakeSeed(version: 1, words: [word('rain', id: 7)]),
    ).loadAll();

    final all = await WordRepository(
      store: store,
      seed: _FakeSeed(
        version: 2,
        words: [word('rain', id: 7), word('weather', id: 1)],
      ),
    ).loadAll();

    final ids = all.map((w) => w.id).toSet();
    expect(ids.length, all.length, reason: '有重複的編號');
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

/// 假題庫。版本與內容都由測試指定。
class _FakeSeed implements SeedSource {
  _FakeSeed({required int version, required this.words}) : _version = version;

  final int _version;
  final List<Word> words;
  int seedCalls = 0;

  @override
  Future<int> version() async => _version;

  @override
  Future<List<Word>> seedWords() async {
    seedCalls++;
    return words;
  }

  @override
  Future<List<Word>> initialImport() async => words;
}

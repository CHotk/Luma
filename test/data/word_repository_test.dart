import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/word_repository.dart';
import 'package:lume/data/seed/seed_source.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/history.dart';
import 'package:lume/domain/models/word.dart';

/// 打包資料同步是最容易寫錯又最難發現的地方：
/// 寫錯就是把成績弄丟，而且要等練兩個月才會發現。
/// 所以這幾個測試比畫面重要得多。
void main() {
  late _MemoryStore store;

  setUp(() => store = _MemoryStore());

  Word word(String w, {int id = 1, int right = 0, int wrong = 0}) => Word(
    id: id,
    word: w,
    pos: 'n.',
    zh: '測試',
    grade: WordGrade.elementary,
    right: right,
    wrong: wrong,
  );

  test('第一次開啟會匯入打包資料並記下版本', () async {
    final repo = WordRepository(
      store: store,
      seed: _FakeSeed(version: 1, words: [word('rain'), word('busy', id: 2)]),
    );

    final all = await repo.loadAll();

    expect(all.length, 2);
    expect(store.data['bundle.version.v1'], '1');
  });

  test('版本沒變就不動資料', () async {
    final seed = _FakeSeed(version: 1, words: [word('rain')]);
    await WordRepository(store: store, seed: seed).loadAll();
    seed.bundleCalls = 0;

    await WordRepository(store: store, seed: seed).loadAll();

    expect(seed.bundleCalls, 0, reason: '版本一樣就不該再去讀打包資料');
  });

  test('版本變新時補上新字，並以打包資料的成績為準', () async {
    await WordRepository(
      store: store,
      seed: _FakeSeed(version: 1, words: [word('rain', right: 1)]),
    ).loadAll();

    final all = await WordRepository(
      store: store,
      seed: _FakeSeed(
        version: 2,
        words: [
          word('rain', right: 3),
          word('weather', id: 2, wrong: 4),
        ],
      ),
    ).loadAll();

    expect(all.length, 2);
    expect(
      all.firstWhere((w) => w.word == 'rain').right,
      3,
      reason: '打包資料是權威，成績要跟著更新',
    );
    expect(all.any((w) => w.word == 'weather'), isTrue, reason: '新字沒補進來');
    expect(store.data['bundle.version.v1'], '2');
  });

  test('打包資料沒有的字保持不動', () async {
    await WordRepository(
      store: store,
      seed: _FakeSeed(version: 1, words: [word('rain'), word('lonely', id: 2)]),
    ).loadAll();

    final all = await WordRepository(
      store: store,
      seed: _FakeSeed(version: 2, words: [word('rain')]),
    ).loadAll();

    expect(all.any((w) => w.word == 'lonely'), isTrue, reason: '本機獨有的字被刪掉了');
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

    expect(all.map((w) => w.id).toSet().length, all.length, reason: '有重複的編號');
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
  _FakeSeed({required int version, required this.words}) : _version = version;

  final int _version;
  final List<Word> words;
  int bundleCalls = 0;

  @override
  int get bundleVersion => _version;

  @override
  Future<List<Word>> bundle() async {
    bundleCalls++;
    return words;
  }

  @override
  Future<List<HistoryEntry>> bundleHistory() async => const [];
}

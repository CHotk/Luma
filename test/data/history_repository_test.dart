import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/history_repository.dart';
import 'package:lume/data/seed/seed_source.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/domain/models/history.dart';
import 'package:lume/domain/models/word.dart';

/// 2026-09-17：一輪的識別／分組徹底從「輪次編號」改成「共用的 at
/// 時戳」，這幾個行為是那次重構的保護，寫錯的話又會悄悄把成績灌水
/// 或讓輪次分組跑掉，所以跟 word_repository_test.dart 一樣值得
/// 花測試盯著。
void main() {
  late _MemoryStore store;

  setUp(() => store = _MemoryStore());

  HistoryEntry log(String w, {required bool ok, required DateTime at}) =>
      HistoryEntry(word: w, correct: ok, at: at);

  test('bundle 版本變新時，指紋比對得上的舊紀錄不會重複疊加', () async {
    store.data['history.entries.v1'] =
        '[{"word":"rain","correct":true,'
        '"at":"2026-09-01T00:10:00.000","typed":false,"input":"",'
        '"seconds":0,"isReview":false}]';
    store.data['history.synced.version'] = '1';

    final seed = _FakeSeed(
      version: 2,
      history: [log('rain', ok: true, at: DateTime(2026, 9, 1, 0, 10))],
    );
    final repo = HistoryRepository(store, seed: seed);

    final entries = await repo.entries();

    expect(entries.length, 1, reason: '指紋（at+word+correct）對得上，不該疊成兩筆');
  });

  test('mergeFromCloud：聯集去重，重複合併不會疊加；輪次留秒數大的', () async {
    final repo = HistoryRepository(store, seed: null);
    final at = DateTime(2026, 9, 20, 9, 0);
    await repo.appendAnswer(log('rain', ok: true, at: at), stealth: false);

    final cloudEntries = [
      log('rain', ok: true, at: at), // 本機已有
      log('snow', ok: false, at: at), // 只有雲端有
    ];
    final cloudRounds = [
      RoundLog(at: at, seconds: 90, total: 2, right: 1, stealth: false),
    ];

    final first = await repo.mergeFromCloud(cloudEntries, cloudRounds);
    final second = await repo.mergeFromCloud(cloudEntries, cloudRounds);

    expect(first, greaterThan(0));
    expect(second, 0, reason: '同樣的雲端資料再合併一次不該有任何異動');
    expect((await repo.entries()).length, 2);
    final rounds = await repo.rounds();
    expect(rounds.length, 1);
    expect(rounds.first.seconds, 90);
  });

  test('appendAnswer：同一個 at 的題目會被歸成同一輪', () async {
    final repo = HistoryRepository(store, seed: null);
    final at = DateTime(2026, 9, 17, 10, 0);

    await repo.appendAnswer(log('rain', ok: true, at: at), stealth: false);
    await repo.appendAnswer(log('busy', ok: false, at: at), stealth: false);

    final rounds = await repo.rounds();
    expect(rounds.length, 1, reason: '兩題共用同一個 at，應該只算一輪');
    expect(rounds.first.total, 2);
    expect(rounds.first.right, 1);

    final forThisRound = await repo.forRound(at);
    expect(forThisRound.map((e) => e.word).toList(), ['rain', 'busy']);
  });

  test('appendAnswer：at 不同就是不同輪', () async {
    final repo = HistoryRepository(store, seed: null);

    await repo.appendAnswer(
      log('rain', ok: true, at: DateTime(2026, 9, 17, 10, 0)),
      stealth: false,
    );
    await repo.appendAnswer(
      log('busy', ok: true, at: DateTime(2026, 9, 17, 10, 5)),
      stealth: false,
    );

    final rounds = await repo.rounds();
    expect(rounds.length, 2, reason: 'at 不一樣就該是不同輪，不能被誤併');
  });

  test('finishRound 用 at 找到對應的輪次補上耗時', () async {
    final repo = HistoryRepository(store, seed: null);
    final at = DateTime(2026, 9, 17, 10, 0);
    await repo.appendAnswer(log('rain', ok: true, at: at), stealth: false);

    await repo.finishRound(at, const Duration(seconds: 42));

    final rounds = await repo.rounds();
    expect(rounds.first.seconds, 42);
  });

  test('輪次列表照真實時間排序', () async {
    final seed = _FakeSeed(
      version: 1,
      history: [
        log('rain', ok: true, at: DateTime(2026, 9, 10)),
        log('busy', ok: true, at: DateTime(2026, 9, 1)),
      ],
    );
    final repo = HistoryRepository(store, seed: seed);

    final rounds = await repo.rounds();

    expect(rounds.map((r) => r.at).toList(), [
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 10),
    ]);
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

class _FakeSeed implements SeedSource {
  _FakeSeed({required int version, this.history = const []}) : _version = version;

  final int _version;
  final List<HistoryEntry> history;

  @override
  int get bundleVersion => _version;

  @override
  Future<List<Word>> bundle() async => const [];

  @override
  Future<List<HistoryEntry>> bundleHistory() async => history;
}

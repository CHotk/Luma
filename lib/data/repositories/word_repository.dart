import 'dart:convert';

import '../../domain/models/quiz.dart';
import '../../domain/models/word.dart';
import '../../domain/scoring.dart';
import '../seed/seed_source.dart';
import '../seed/word_seed_loader.dart';
import '../storage/key_value_store.dart';

/// 單字庫的唯一入口。
///
/// 畫面層只准透過這個類別拿字，不准自己去碰儲存或資產檔。
class WordRepository {
  WordRepository({required KeyValueStore store, SeedSource? seed})
    : _store = store,
      _seed = seed ?? WordSeedLoader();

  static const _wordsKey = 'words.v1';
  static const _seedVersionKey = 'seed.version.v1';

  final KeyValueStore _store;
  final SeedSource _seed;

  /// 記憶體快取。一輪之中會被讀很多次，不要每次都去解 JSON。
  List<Word>? _cache;

  /// 讀出全部單字。
  ///
  /// 第一次開啟從打包的資料匯入，之後都讀本機儲存。
  /// 每次讀取都會順便檢查題庫有沒有出新版，有的話把新字補進來。
  Future<List<Word>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _store.read(_wordsKey);
    if (raw == null) {
      final seeded = await _seed.initialImport();
      await _persist(seeded);
      await _store.write(_seedVersionKey, '${await _seed.version()}');
      return _cache = seeded;
    }

    final stored = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Word.fromJson)
        .toList();
    return _cache = await _mergeNewSeedWords(stored);
  }

  /// 題庫升級。
  ///
  /// 題庫之後一定會再長（國中的 G 到 Z 還沒補完），
  /// 但本機那份資料帶著使用者的成績，絕對不能整包覆蓋。
  /// 所以這裡只做一件事：把本機沒有的字加進去，既有的一個都不動。
  Future<List<Word>> _mergeNewSeedWords(List<Word> current) async {
    final applied = int.tryParse(await _store.read(_seedVersionKey) ?? '') ?? 0;
    final latest = await _seed.version();
    if (latest <= applied) return current;

    final known = {for (final w in current) w.word.toLowerCase()};
    var nextId = current.fold<int>(0, (max, w) => w.id > max ? w.id : max);

    final additions = <Word>[];
    for (final candidate in await _seed.seedWords()) {
      if (known.contains(candidate.word.toLowerCase())) continue;
      additions.add(candidate.copyWith(id: ++nextId));
    }

    final merged = [...current, ...additions];
    await _persist(merged);
    await _store.write(_seedVersionKey, '$latest');
    return merged;
  }

  /// 把一輪的結果寫回去。
  ///
  /// 換算交給 [Scoring]，這裡只負責合併與保存，職責分開才好測。
  Future<List<Word>> applyRound(RoundResult result) async {
    final all = await loadAll();
    final updates = Scoring.applyRound(result);
    final merged = [for (final w in all) updates[w.id] ?? w];
    _cache = merged;
    await _persist(merged);
    return merged;
  }

  /// 清掉本機資料，下次讀取會重新從打包的資料匯入。
  /// 這會連成績一起清掉，設定頁要接上去時記得先跳確認。
  Future<void> resetToSeed() async {
    _cache = null;
    await _store.remove(_wordsKey);
    await _store.remove(_seedVersionKey);
  }

  Future<void> _persist(List<Word> words) async {
    await _store.write(_wordsKey, jsonEncode([for (final w in words) w.toJson()]));
  }
}

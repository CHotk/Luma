import 'dart:convert';

import '../../domain/models/quiz.dart';
import '../../domain/models/word.dart';
import '../../domain/scoring.dart';
import '../seed/word_seed_loader.dart';
import '../storage/key_value_store.dart';

/// 單字庫的唯一入口。
///
/// 畫面層只准透過這個類別拿字，不准自己去碰儲存或資產檔。
class WordRepository {
  WordRepository({required KeyValueStore store, WordSeedLoader? loader})
    : _store = store,
      _loader = loader ?? WordSeedLoader();

  static const _key = 'words.v1';

  final KeyValueStore _store;
  final WordSeedLoader _loader;

  /// 記憶體快取。一輪之中會被讀很多次，不要每次都去解 JSON。
  List<Word>? _cache;

  /// 讀出全部單字。第一次開啟時從打包的資料匯入，之後都讀本機儲存。
  Future<List<Word>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _store.read(_key);
    if (raw == null) {
      final seeded = await _loader.load();
      _cache = seeded;
      await _persist(seeded);
      return seeded;
    }

    final decoded = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Word.fromJson)
        .toList();
    _cache = decoded;
    return decoded;
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
  /// 開發期間用得到，設定頁之後也會用到。
  Future<void> resetToSeed() async {
    _cache = null;
    await _store.remove(_key);
  }

  Future<void> _persist(List<Word> words) async {
    await _store.write(_key, jsonEncode([for (final w in words) w.toJson()]));
  }
}

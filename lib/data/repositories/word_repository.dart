import 'dart:convert';

import '../../domain/models/word.dart';
import '../seed/seed_source.dart';
import '../seed/word_seed_loader.dart';
import '../storage/key_value_store.dart';
import 'history_repository.dart';

/// 單字庫的唯一入口。
///
/// 這裡存的是單字的「靜態資料」：拼字、詞性、中文、階段、例句、配圖。
/// **對錯次數不存在這裡**，那是從 [HistoryRepository] 的紀錄加總出來的。
///
/// 這樣分是為了讓兩邊都能出題：對話那邊考完往紀錄追加，App 考完也追加，
/// 合併時去重就好，沒有人的成績會被對方蓋掉。
class WordRepository {
  WordRepository({
    required KeyValueStore store,
    required HistoryRepository history,
    SeedSource? seed,
  }) : _store = store,
       _history = history,
       _seed = seed ?? WordSeedLoader();

  static const _wordsKey = 'words.v1';
  static const _bundleVersionKey = 'bundle.version.v1';

  final KeyValueStore _store;
  final HistoryRepository _history;
  final SeedSource _seed;

  /// 記憶體快取。一輪之中會被讀很多次，不要每次都去解 JSON 又重算加總。
  List<Word>? _cache;

  /// 讀出全部單字，對錯次數已經依紀錄算好。
  Future<List<Word>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final base = await _loadBase();
    final tally = await _history.tally();

    return _cache = [
      for (final w in base)
        () {
          final t = tally[w.word.toLowerCase()];
          return t == null
              ? w
              : w.copyWith(
                  right: t.right,
                  wrong: t.wrong,
                  lastTest: t.lastTest,
                );
        }(),
    ];
  }

  /// 作答之後呼叫，讓下次讀取重新加總。
  /// 紀錄本身由 [HistoryRepository] 負責寫，這裡只管把快取丟掉。
  void invalidate() => _cache = null;

  /// 清掉本機資料，下次讀取會重新從打包的資料匯入。
  Future<void> resetToBundle() async {
    _cache = null;
    await _store.remove(_wordsKey);
    await _store.remove(_bundleVersionKey);
  }

  /// 靜態資料。第一次開啟從打包資料匯入，之後讀本機，
  /// 打包版本變新時同步。
  Future<List<Word>> _loadBase() async {
    final raw = await _store.read(_wordsKey);
    if (raw == null) {
      final seeded = await _seed.bundle();
      await _persist(seeded);
      await _store.write(_bundleVersionKey, '${_seed.bundleVersion}');
      return seeded;
    }

    final stored = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Word.fromJson)
        .toList();
    return _syncBundle(stored);
  }

  /// 打包資料升級。
  ///
  /// 只同步靜態欄位：中文、詞性、階段、例句、加入日期。
  /// **不碰對錯次數**，那是算出來的，碰了只會讓兩邊的紀錄對不起來。
  /// App 裡有、打包資料沒有的字一律保留。
  Future<List<Word>> _syncBundle(List<Word> current) async {
    final applied =
        int.tryParse(await _store.read(_bundleVersionKey) ?? '') ?? 0;
    if (_seed.bundleVersion <= applied) return current;

    final incoming = {
      for (final w in await _seed.bundle()) w.word.toLowerCase(): w,
    };
    var nextId = current.fold<int>(0, (max, w) => w.id > max ? w.id : max);

    final merged = <Word>[];
    for (final local in current) {
      final fresh = incoming.remove(local.word.toLowerCase());
      merged.add(
        fresh == null
            ? local
            : local.copyWith(
                // 靜態欄位以打包資料為準：題庫改了中文或加了分類就會同步過來。
                senseCount: fresh.senseCount,
                example: fresh.example,
                added: fresh.added,
                tags: fresh.tags,
                relatedWords: fresh.relatedWords,
              ),
      );
    }
    for (final added in incoming.values) {
      merged.add(added.copyWith(id: ++nextId));
    }

    await _persist(merged);
    await _store.write(_bundleVersionKey, '${_seed.bundleVersion}');
    return merged;
  }

  Future<void> _persist(List<Word> words) async =>
      _store.write(_wordsKey, jsonEncode([for (final w in words) w.toJson()]));
}

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
  static const _bundleVersionKey = 'bundle.version.v1';

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
      final seeded = await _seed.bundle();
      await _persist(seeded);
      await _store.write(_bundleVersionKey, '${_seed.bundleVersion}');
      return _cache = seeded;
    }

    final stored = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Word.fromJson)
        .toList();
    return _cache = await _syncBundle(stored);
  }

  /// 打包資料升級。
  ///
  /// 兩種情況會用到：題庫長大（國中的 G 到 Z 還沒補完），
  /// 或是 En 資料夾那邊的成績有更新。
  ///
  /// 合併規則說清楚，因為這段會動到成績：
  ///   打包資料裡有的字 → 對錯次數以打包資料為準，直接覆蓋。
  ///   打包資料沒有、App 裡有的字 → 完全不動。
  ///   打包資料有、App 沒有的字 → 新增，編號接在最大號後面。
  ///
  /// 覆蓋是刻意的：切換到 App 之前，En 資料夾那邊才是權威。
  /// 等到不再從那邊同步，[SeedSource.bundleVersion] 就不會再變，這段自然不會跑。
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
                right: fresh.right,
                wrong: fresh.wrong,
                lastTest: fresh.lastTest,
              ),
      );
    }
    // 剩下的就是 App 還沒有的字，接在後面。
    for (final added in incoming.values) {
      merged.add(added.copyWith(id: ++nextId));
    }

    await _persist(merged);
    await _store.write(_bundleVersionKey, '${_seed.bundleVersion}');
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
    await _store.remove(_bundleVersionKey);
  }

  Future<void> _persist(List<Word> words) async {
    await _store.write(_wordsKey, jsonEncode([for (final w in words) w.toJson()]));
  }
}

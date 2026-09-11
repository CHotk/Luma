import 'dart:convert';

import '../../domain/models/history.dart';
import '../seed/seed_source.dart';
import '../storage/key_value_store.dart';

/// 總歷史紀錄，也是整套資料的權威。
///
/// 規矩只有一條：**只增不改**。
/// 單字上的對錯次數不再自己累加，一律從這裡加總算出來，
/// 所以兩邊（對話與 App）各自考完各自追加，合併時去重就不會有人的紀錄被吃掉。
class HistoryRepository {
  HistoryRepository(this._store, {SeedSource? seed}) : _seed = seed;

  static const _entriesKey = 'history.entries.v1';
  static const _roundsKey = 'history.rounds.v1';
  static const _syncedKey = 'history.synced.version';

  final KeyValueStore _store;

  /// 打包資料來源。給 null 就不做合併，測試會這樣用。
  final SeedSource? _seed;

  Future<List<HistoryEntry>> entries() async {
    await _syncBundle();
    return _readEntries();
  }

  Future<List<RoundLog>> rounds() async {
    await _syncBundle();
    return _readRounds();
  }

  /// 每個字的對錯次數與最後受測日期，一次算好給單字庫用。
  /// 鍵是小寫的單字。
  Future<Map<String, WordTally>> tally() async {
    final result = <String, WordTally>{};
    for (final e in await entries()) {
      final key = e.word.toLowerCase();
      final current = result[key] ?? const WordTally();
      result[key] = current.plus(correct: e.correct, at: e.at);
    }
    return result;
  }

  /// 下一輪要用的編號，接在現有最大號之後。
  ///
  /// 兩邊可能剛好拿到同一個號碼，但那沒關係：
  /// 編號只是顯示用，去重看的是內容。
  Future<int> nextRoundNumber() async {
    final past = await rounds();
    if (past.isEmpty) return 1;
    return past.map((r) => r.round).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// 每答完一題就寫一次。
  ///
  /// 不等整輪結束才寫，是因為中途關掉瀏覽器或被系統收掉的話，
  /// 那一輪的努力就全部不見了。寧可留下半輪，也不要留下空白。
  Future<void> appendAnswer(HistoryEntry entry, {required bool stealth}) async {
    final all = [...await entries(), entry];
    await _writeEntries(all);

    // 順手把這一輪的摘要更新到目前為止的狀態，半途中斷也看得出考到哪。
    final mine = all.where((e) => e.round == entry.round).toList();
    final summary = RoundLog(
      round: entry.round,
      at: mine.first.at,
      seconds: mine.fold(0, (sum, e) => sum + e.seconds),
      total: mine.length,
      right: mine.where((e) => e.correct).length,
      stealth: stealth,
    );

    final rounds = await _readRounds();
    final index = rounds.indexWhere((r) => r.round == entry.round);
    if (index >= 0) {
      rounds[index] = summary;
    } else {
      rounds.add(summary);
    }
    await _writeRounds(rounds..sort((a, b) => a.round.compareTo(b.round)));
  }

  /// 一輪結束時把摘要補上真正的耗時。
  ///
  /// 每題累加的秒數只算「想的時間」，這裡改成整輪實際花的時間，
  /// 含翻卡片、看答案、發呆那些。
  Future<void> finishRound(int round, Duration elapsed) async {
    final rounds = await _readRounds();
    final index = rounds.indexWhere((r) => r.round == round);
    if (index < 0) return;
    final current = rounds[index];
    rounds[index] = RoundLog(
      round: current.round,
      at: current.at,
      seconds: elapsed.inSeconds,
      total: current.total,
      right: current.right,
      stealth: current.stealth,
    );
    await _writeRounds(rounds);
  }

  /// 從第一天到現在的總計。即時算出來，不另外存一份。
  Future<LifetimeStats> lifetime() async {
    final all = await rounds();
    if (all.isEmpty) return LifetimeStats.empty;

    var questions = 0, right = 0, seconds = 0, stealth = 0;
    final days = <String>{};
    for (final r in all) {
      questions += r.total;
      right += r.right;
      seconds += r.seconds;
      if (r.stealth) stealth++;
      days.add('${r.at.year}-${r.at.month}-${r.at.day}');
    }

    return LifetimeStats(
      rounds: all.length,
      questions: questions,
      right: right,
      wrong: questions - right,
      seconds: seconds,
      activeDays: days.length,
      stealthRounds: stealth,
      since: all.first.at,
    );
  }

  /// 某一輪的所有題目，照作答順序。
  /// 總紀錄頁點某一輪進去就是看這個。
  Future<List<HistoryEntry>> forRound(int round) async {
    final all = await entries();
    return all.where((e) => e.round == round).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  /// 某個字的所有作答紀錄，新的排前面。
  Future<List<HistoryEntry>> forWord(String word) async {
    final key = word.toLowerCase();
    final all = await entries();
    return all.where((e) => e.word.toLowerCase() == key).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  /// 把打包進來的紀錄合併進本機。
  ///
  /// 每次打包版本變新就跑一次，不是只跑一次。
  /// 對話那邊考完也是往同一份 history.txt 追加，所以這裡要能反覆合併。
  ///
  /// 去重看的是內容，不是編號：同一輪、同一個字、同一個時間點、同樣對錯，
  /// 就算是同一筆。兩邊剛好用到同一個輪次編號也不會互相蓋掉。
  Future<void> _syncBundle() async {
    final seed = _seed;
    if (seed == null) return;
    final applied = int.tryParse(await _store.read(_syncedKey) ?? '') ?? 0;
    if (seed.bundleVersion <= applied) return;

    // 先插旗再合併。就算中途出錯也不要無限重試。
    await _store.write(_syncedKey, '${seed.bundleVersion}');

    final incoming = await seed.bundleHistory();
    if (incoming.isEmpty) return;

    final existing = await _readEntries();
    final seen = {for (final e in existing) _fingerprint(e)};
    final added = [
      for (final e in incoming)
        if (seen.add(_fingerprint(e))) e,
    ];
    if (added.isEmpty) return;

    final merged = [...existing, ...added]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _writeEntries(merged);
    await _writeRounds(_rebuildRounds(merged, await _readRounds()));
  }

  static String _fingerprint(HistoryEntry e) =>
      '${e.round}|${e.word.toLowerCase()}|${e.at.toIso8601String()}|${e.correct}';

  /// 依合併後的紀錄重建每輪摘要。
  ///
  /// App 自己跑出來的輪次有秒數與偽裝標記，那些要留著；
  /// 其餘從紀錄兜回來，秒數是 0，因為 history.txt 本來就沒有時間。
  List<RoundLog> _rebuildRounds(
    List<HistoryEntry> entries,
    List<RoundLog> known,
  ) {
    final byRound = <int, List<HistoryEntry>>{};
    for (final e in entries) {
      byRound.putIfAbsent(e.round, () => []).add(e);
    }
    final keep = {for (final r in known) r.round: r};

    return [
      for (final entry in byRound.entries)
        keep[entry.key] ??
            RoundLog(
              round: entry.key,
              at: entry.value.first.at,
              seconds: 0,
              total: entry.value.length,
              right: entry.value.where((e) => e.correct).length,
              stealth: false,
            ),
    ]..sort((a, b) => a.round.compareTo(b.round));
  }

  Future<List<HistoryEntry>> _readEntries() async {
    final raw = await _store.read(_entriesKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(HistoryEntry.fromJson)
        .toList();
  }

  Future<List<RoundLog>> _readRounds() async {
    final raw = await _store.read(_roundsKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(RoundLog.fromJson)
        .toList();
  }

  Future<void> _writeEntries(List<HistoryEntry> entries) => _store.write(
    _entriesKey,
    jsonEncode([for (final e in entries) e.toJson()]),
  );

  Future<void> _writeRounds(List<RoundLog> rounds) => _store.write(
    _roundsKey,
    jsonEncode([for (final r in rounds) r.toJson()]),
  );
}

/// 單一個字的加總結果。
class WordTally {
  const WordTally({this.right = 0, this.wrong = 0, this.lastTest});

  final int right;
  final int wrong;
  final DateTime? lastTest;

  WordTally plus({required bool correct, required DateTime at}) {
    final latest = lastTest == null || at.isAfter(lastTest!) ? at : lastTest;
    return WordTally(
      right: correct ? right + 1 : right,
      wrong: correct ? wrong : wrong + 1,
      lastTest: latest,
    );
  }
}

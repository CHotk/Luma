import 'dart:convert';

import '../../domain/models/history.dart';
import '../../domain/models/quiz.dart';
import '../seed/seed_source.dart';
import '../storage/key_value_store.dart';

/// 總歷史紀錄。
///
/// 兩份資料：每一題的作答紀錄、每一輪的摘要。
/// 兩份都是只增不改，任何情況都不准去改既有的項目，
/// 因為單字上的對錯次數就是靠這裡加總出來的。
class HistoryRepository {
  HistoryRepository(this._store, {SeedSource? seed}) : _seed = seed;

  static const _entriesKey = 'history.entries.v1';
  static const _roundsKey = 'history.rounds.v1';
  static const _importedKey = 'history.imported.v1';

  final KeyValueStore _store;

  /// 打包資料來源。給 null 就不做匯入，測試會這樣用。
  final SeedSource? _seed;

  Future<List<HistoryEntry>> entries() async {
    await _importOnce();
    return _readEntries();
  }

  Future<List<RoundLog>> rounds() async {
    await _importOnce();
    return _readRounds();
  }

  /// 一輪結束時追加。輪次編號自己接續，呼叫端不用管。
  Future<void> appendRound(RoundResult result, {required bool stealth}) async {
    await _importOnce();
    final pastRounds = await _readRounds();
    final roundNo = pastRounds.isEmpty ? 1 : pastRounds.last.round + 1;

    final appended = [
      ...await _readEntries(),
      for (final a in result.answers)
        HistoryEntry(
          round: roundNo,
          word: a.question.word.word,
          correct: a.correct,
          at: a.answeredAt,
          seconds: a.seconds,
        ),
    ];

    await _writeEntries(appended);
    await _writeRounds([
      ...pastRounds,
      RoundLog(
        round: roundNo,
        at: result.finishedAt,
        seconds: result.elapsed.inSeconds,
        total: result.total,
        right: result.rightCount,
        stealth: stealth,
      ),
    ]);
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

  /// 某個字的所有作答紀錄，新的排前面。
  /// 單字詳情頁要看「幾月幾日幾點考過、對還是錯」就是讀這個。
  Future<List<HistoryEntry>> forWord(String word) async {
    final key = word.toLowerCase();
    final all = await entries();
    return all.where((e) => e.word.toLowerCase() == key).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  /// 把 En 資料夾那邊累積的紀錄搬進來，一輩子只做一次。
  ///
  /// 輪次編號會撞號，因為兩邊都是從 1 開始編。
  /// 處理方式是舊紀錄保留原本的編號，App 自己已經做過的輪次往後推。
  /// 這是唯一一次會動到既有紀錄的地方，而且只動編號不動內容。
  Future<void> _importOnce() async {
    final seed = _seed;
    if (seed == null) return;
    if (await _store.read(_importedKey) != null) return;

    // 先插旗再匯入。就算中途出錯也不要無限重試，
    // 重試只會把同一批紀錄灌進去兩次。
    await _store.write(_importedKey, '1');

    final incoming = await seed.bundleHistory();
    if (incoming.isEmpty) return;

    final offset = incoming.fold<int>(
      0,
      (max, e) => e.round > max ? e.round : max,
    );

    final shiftedEntries = [
      for (final e in await _readEntries())
        HistoryEntry(
          round: e.round + offset,
          word: e.word,
          correct: e.correct,
          at: e.at,
          seconds: e.seconds,
        ),
    ];
    final shiftedRounds = [
      for (final r in await _readRounds())
        RoundLog(
          round: r.round + offset,
          at: r.at,
          seconds: r.seconds,
          total: r.total,
          right: r.right,
          stealth: r.stealth,
        ),
    ];

    await _writeEntries([...incoming, ...shiftedEntries]);
    await _writeRounds([..._rebuildRounds(incoming), ...shiftedRounds]);
  }

  /// 舊紀錄只有一行一題，沒有每輪的摘要，所以要自己兜回來。
  /// 秒數一律 0，因為 history.txt 本來就沒記時間。
  List<RoundLog> _rebuildRounds(List<HistoryEntry> entries) {
    final byRound = <int, List<HistoryEntry>>{};
    for (final e in entries) {
      byRound.putIfAbsent(e.round, () => []).add(e);
    }

    final rounds = [
      for (final entry in byRound.entries)
        RoundLog(
          round: entry.key,
          at: entry.value.first.at,
          seconds: 0,
          total: entry.value.length,
          right: entry.value.where((e) => e.correct).length,
          stealth: false,
        ),
    ]..sort((a, b) => a.round.compareTo(b.round));
    return rounds;
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

  Future<void> _writeEntries(List<HistoryEntry> entries) =>
      _store.write(_entriesKey, jsonEncode([for (final e in entries) e.toJson()]));

  Future<void> _writeRounds(List<RoundLog> rounds) =>
      _store.write(_roundsKey, jsonEncode([for (final r in rounds) r.toJson()]));
}

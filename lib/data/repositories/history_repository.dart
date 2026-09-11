import 'dart:convert';

import '../../domain/models/history.dart';
import '../../domain/models/quiz.dart';
import '../storage/key_value_store.dart';

/// 總歷史紀錄。
///
/// 兩份資料：每一題的作答紀錄、每一輪的摘要。
/// 兩份都是只增不改，任何情況都不准去改既有的項目，
/// 因為單字上的對錯次數就是靠這裡加總出來的。
class HistoryRepository {
  HistoryRepository(this._store);

  static const _entriesKey = 'history.entries.v1';
  static const _roundsKey = 'history.rounds.v1';

  final KeyValueStore _store;

  Future<List<HistoryEntry>> entries() async {
    final raw = await _store.read(_entriesKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(HistoryEntry.fromJson)
        .toList();
  }

  Future<List<RoundLog>> rounds() async {
    final raw = await _store.read(_roundsKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(RoundLog.fromJson)
        .toList();
  }

  /// 一輪結束時追加。輪次編號自己接續，呼叫端不用管。
  Future<void> appendRound(
    RoundResult result, {
    required bool stealth,
  }) async {
    final pastRounds = await rounds();
    final roundNo = pastRounds.isEmpty ? 1 : pastRounds.last.round + 1;

    final pastEntries = await entries();
    final appended = [
      ...pastEntries,
      for (final a in result.answers)
        HistoryEntry(
          round: roundNo,
          word: a.question.word.word,
          correct: a.correct,
          at: result.finishedAt,
        ),
    ];

    await _store.write(
      _entriesKey,
      jsonEncode([for (final e in appended) e.toJson()]),
    );
    await _store.write(
      _roundsKey,
      jsonEncode([
        for (final r in pastRounds) r.toJson(),
        RoundLog(
          round: roundNo,
          at: result.finishedAt,
          seconds: result.elapsed.inSeconds,
          total: result.total,
          right: result.rightCount,
          stealth: stealth,
        ).toJson(),
      ]),
    );
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
}

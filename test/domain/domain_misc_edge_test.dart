import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/daily_limit.dart';
import 'package:lume/domain/drinking_stats.dart' as dk;
import 'package:lume/domain/models/drinking_entry.dart';
import 'package:lume/domain/models/fitness.dart';
import 'package:lume/domain/models/kana_exam.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/domain/models/note_collection.dart';
import 'package:lume/domain/models/quiz.dart';
import 'package:lume/domain/models/smoking_entry.dart';
import 'package:lume/domain/models/sync_log_entry.dart';
import 'package:lume/domain/models/word.dart';
import 'package:lume/domain/smoking_stats.dart' as sm;

/// 算法與資料格式的邊界（2026-11-12 使用者：每個功能都補到 95%、更多邊界）：
/// 抽菸／喝酒統計（各自一份）、健身類型、作答結果、單字分級、50 音考試舊資料、
/// 音樂清單、同步紀錄亂寫的動作、每日用量。
void main() {
  final now = DateTime(2026, 11, 12, 15, 0);

  group('抽菸統計', () {
    List<SmokingEntry> es(List<DateTime> ts, [List<String?>? reasons]) => [
      for (var i = 0; i < ts.length; i++)
        SmokingEntry(id: '$i', at: ts[i], reason: reasons?[i]),
    ];

    test('每天幾次、最近 N 天（沒有的補 0）', () {
      final e = es([
        DateTime(2026, 11, 12, 8),
        DateTime(2026, 11, 12, 9),
        DateTime(2026, 11, 10, 9),
      ]);
      expect(sm.countsByDay(e)[DateTime(2026, 11, 12)], 2);
      final last = sm.lastDays(e, now, 3);
      expect(last.map((d) => d.count), [1, 0, 2]);
      expect(last.first.day, DateTime(2026, 11, 10));
    });

    test('平均間隔：不到兩筆＝null；只看 since 之後', () {
      expect(sm.averageInterval(es([now]), DateTime(2000)), isNull);
      final e = es([
        DateTime(2026, 11, 12, 8),
        DateTime(2026, 11, 12, 10),
        DateTime(2026, 11, 12, 14),
        DateTime(2026, 11, 1),
      ]);
      expect(
        sm.averageInterval(e, DateTime(2026, 11, 12)),
        const Duration(hours: 3),
      );
    });

    test('一天內最長間隔：沒有＝null；今天要算到現在；別天不算', () {
      expect(sm.longestGapOnDay(const [], now, now), isNull);
      final today = es([DateTime(2026, 11, 12, 8), DateTime(2026, 11, 12, 9)]);
      expect(sm.longestGapOnDay(today, now, now), const Duration(hours: 6));
      final other = es([DateTime(2026, 11, 1, 8), DateTime(2026, 11, 1, 12)]);
      expect(
        sm.longestGapOnDay(other, DateTime(2026, 11, 1), now),
        const Duration(hours: 4),
      );
    });

    test('時段：22 點、5 點算深夜；6、12、18 點的邊界；原因沒填＝未填；時間格式', () {
      expect(sm.timeBucket(DateTime(2026, 1, 1, 22)), '深夜 22–06');
      expect(sm.timeBucket(DateTime(2026, 1, 1, 5)), '深夜 22–06');
      expect(sm.timeBucket(DateTime(2026, 1, 1, 6)), '早上 06–12');
      expect(sm.timeBucket(DateTime(2026, 1, 1, 12)), '下午 12–18');
      expect(sm.timeBucket(DateTime(2026, 1, 1, 18)), '晚上 18–22');
      final e = es(
        [DateTime(2026, 1, 1, 7), DateTime(2026, 1, 1, 23)],
        ['壓力', null],
      );
      expect(sm.countsByBucket(e)['早上 06–12'], 1);
      expect(sm.countsByBucket(e)['下午 12–18'], 0);
      expect(sm.countsByReason(e), {'壓力': 1, '未填': 1});
      expect(sm.formatDuration(const Duration(minutes: 5)), '5 分');
      expect(
        sm.formatDuration(const Duration(hours: 2, minutes: 3)),
        '2 小時 3 分',
      );
    });
  });

  group('喝酒統計（獨立一份）', () {
    List<DrinkingEntry> es(List<DateTime> ts, [List<String?>? reasons]) => [
      for (var i = 0; i < ts.length; i++)
        DrinkingEntry(id: '$i', at: ts[i], reason: reasons?[i]),
    ];

    test('每天、最近 N 天、平均間隔、最長間隔、時段、原因、格式', () {
      final e = es(
        [
          DateTime(2026, 11, 12, 20),
          DateTime(2026, 11, 12, 23),
          DateTime(2026, 11, 11, 13),
        ],
        ['聚餐', null, '聚餐'],
      );
      expect(dk.countsByDay(e)[DateTime(2026, 11, 12)], 2);
      expect(dk.lastDays(e, now, 2).map((d) => d.count), [1, 2]);
      expect(
        dk.averageInterval(e, DateTime(2026, 11, 12)),
        const Duration(hours: 3),
      );
      expect(dk.averageInterval(const [], DateTime(2000)), isNull);
      expect(
        dk.longestGapOnDay(e, DateTime(2026, 11, 12), DateTime(2026, 11, 13)),
        const Duration(hours: 3),
      );
      expect(dk.longestGapOnDay(const [], now, now), isNull);
      expect(
        dk.longestGapOnDay(es([DateTime(2026, 11, 12, 8)]), now, now),
        const Duration(hours: 7),
      );
      expect(dk.timeBucket(DateTime(2026, 1, 1, 3)), '深夜 22–06');
      expect(dk.timeBucket(DateTime(2026, 1, 1, 9)), '早上 06–12');
      expect(dk.timeBucket(DateTime(2026, 1, 1, 13)), '下午 12–18');
      expect(dk.timeBucket(DateTime(2026, 1, 1, 20)), '晚上 18–22');
      expect(dk.countsByBucket(e)['晚上 18–22'], 1);
      expect(dk.countsByReason(e), {'聚餐': 2, '未填': 1});
      expect(dk.formatDuration(const Duration(hours: 1)), '1 小時 0 分');
      expect(dk.formatDuration(const Duration(minutes: 59)), '59 分');
      expect(dk.dayOf(DateTime(2026, 1, 1, 23, 59)), DateTime(2026, 1, 1));
    });
  });

  test('健身類型：每種都有名稱、圖示、顏色；存的值讀回來；亂寫的當重訓', () {
    for (final t in FitnessType.values) {
      expect(t.label, isNotEmpty);
      expect(t.emoji, isNotEmpty);
      expect(t.color.a, greaterThan(0));
      expect(FitnessTypeX.fromStorage(t.storageValue), t);
    }
    expect(FitnessTypeX.fromStorage('亂寫'), FitnessType.strength);
  });

  test('作答結果：總數、答對、答錯清單、新字／待複習／已掌握分開算', () {
    QuizAnswer a(bool review, bool ok, {bool mastered = false}) => QuizAnswer(
      question: QuizQuestion(
        word: const Word(
          id: 1,
          word: 'w',
          pos: 'n',
          zh: '字',
          grade: WordGrade.junior,
        ),
        mode: QuizMode.tap,
        isReview: review,
        isMasteredReview: mastered,
      ),
      correct: ok,
      answeredAt: now,
      seconds: 2,
    );
    final r = RoundResult(
      answers: [
        a(false, true),
        a(false, false),
        a(true, true),
        a(true, true, mastered: true),
        a(true, false, mastered: true),
      ],
      elapsed: const Duration(seconds: 30),
      finishedAt: now,
    );
    expect(r.total, 5);
    expect(r.rightCount, 3);
    expect(r.missed, hasLength(2));
    expect(r.countOf(review: false, correctOnly: false), 2);
    expect(r.countOf(review: false, correctOnly: true), 1);
    expect(r.countOf(review: true, correctOnly: true), 1);
    expect(r.masteredCount(correctOnly: false), 2);
    expect(r.masteredCount(correctOnly: true), 1);
  });

  test('單字：舊的細分級收斂（小／國）、看不懂當國小；詞義標記；狀態排序', () {
    expect(WordGrade.parse('小三'), WordGrade.elementary);
    expect(WordGrade.parse('國二'), WordGrade.junior);
    expect(WordGrade.parse('亂寫'), WordGrade.elementary);
    expect(WordSenseCount.none.isTagged, isFalse);
    expect(WordSenseCount.values.last.isTagged, isTrue);
    expect(
      WordStatus.pending.priority,
      lessThan(WordStatus.confirmed.priority),
    );
    expect(WordStatus.untested.priority, 1);
    const w = Word(
      id: 1,
      word: 'w',
      pos: 'n',
      zh: '字',
      grade: WordGrade.junior,
    );
    expect(w.isUntested, isTrue);
  });

  test('50 音考試：舊資料沒有 roundId＝用自己的 id；JSON 來回保留筆畫', () {
    final old = KanaExamEntry.fromJson({
      'id': 'x',
      'kana': 'あ',
      'romaji': 'a',
      'isCorrect': true,
      'examType': 'hira',
      'savedAt': '2026-11-01T00:00:00.000',
    });
    expect(old.roundId, 'x');
    expect(old.strokes, isEmpty);
    expect(old.syncedAt, DateTime(2026, 11, 1));
    final full = KanaExamEntry(
      id: 'y',
      roundId: 'r',
      kana: 'い',
      romaji: 'i',
      isCorrect: false,
      examType: 'hira',
      savedAt: DateTime(2026, 11, 1),
      strokes: const [
        [(1.0, 2.0, 3.0)],
      ],
      lightRow: 'あ行',
      writeMs: 1200,
      updatedAt: DateTime(2026, 11, 2),
      deletedAt: DateTime(2026, 11, 3),
    );
    final back = KanaExamEntry.fromJson(jsonDecode(jsonEncode(full.toJson())));
    expect(back.strokes.single.single, (1.0, 2.0, 3.0));
    expect(back.lightRow, 'あ行');
    expect(back.writeMs, 1200);
    expect(back.deletedAt, DateTime(2026, 11, 3));
    expect(back.syncedAt, DateTime(2026, 11, 2));
  });

  test('音樂清單：喜歡的清單、copyWith、JSON 來回（缺欄位用預設）', () {
    final p = MusicPlaylist(
      id: 'p',
      name: '清單',
      versionIds: const ['a'],
      updatedAt: DateTime.utc(2026),
    );
    expect(p.isLiked, isFalse);
    final q = p.copyWith(
      name: '改',
      versionIds: const ['a', 'b'],
      deletedAt: DateTime.utc(2026, 2),
    );
    final back = MusicPlaylist.fromJson(jsonDecode(jsonEncode(q.toJson())));
    expect(back.name, '改');
    expect(back.versionIds, ['a', 'b']);
    expect(back.deletedAt!.isAtSameMomentAs(DateTime.utc(2026, 2)), isTrue);
    final bare = MusicPlaylist.fromJson({'id': 'z'});
    expect(bare.name, '');
    expect(bare.versionIds, isEmpty);
  });

  test('同步紀錄：動作名稱、亂寫的動作當同步；用量 copyWith', () {
    expect(SyncLogAction.sync.label, '同步');
    expect(SyncLogAction.backup.label, '備份下載');
    final e = SyncLogEntry.fromJson({
      'at': '2026-11-01T00:00:00.000',
      'action': '亂寫',
      'success': false,
    });
    expect(e.action, SyncLogAction.sync);
    final u = DailyUsage(date: now).copyWith(roundsDone: 2);
    expect(u.roundsDone, 2);
    expect(u.copyWith(practiceSeconds: 9).practiceSeconds, 9);
    expect(u.copyWith(practiceSeconds: 9).roundsDone, 2);
  });

  test('筆記本：讀名稱、亂寫的用第一本', () {
    for (final c in NoteCollection.values) {
      expect(NoteCollection.parse(c.name), c);
    }
    expect(NoteCollection.parse('亂寫'), NoteCollection.values.first);
    expect(NoteCollection.parse(null), NoteCollection.values.first);
  });
}

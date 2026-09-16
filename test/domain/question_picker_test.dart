import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/quiz.dart';
import 'package:lume/domain/models/word.dart';
import 'package:lume/domain/question_picker.dart';
import 'package:lume/domain/rules_config.dart';

/// 一輪的組成是這個 App 的核心規則，改壞了不會當掉，
/// 只會讓人考了兩個月才發現錯過的字從來沒回來過。
void main() {
  final now = DateTime(2026, 9, 11);

  Word word(
    String w, {
    required int id,
    int right = 0,
    int wrong = 0,
    DateTime? lastTest,
    List<String> tags = const [],
  }) => Word(
    id: id,
    word: w,
    pos: 'n.',
    zh: '測試',
    grade: WordGrade.elementary,
    right: right,
    wrong: wrong,
    lastTest: lastTest,
    tags: tags,
  );

  Word sentence(
    String w, {
    required int id,
    int right = 0,
    int wrong = 0,
    DateTime? lastTest,
  }) => word(
    w,
    id: id,
    right: right,
    wrong: wrong,
    lastTest: lastTest,
    tags: const [sentenceTag],
  );

  /// 30 個沒考過、5 個答錯過還沒答對、3 個答對一次的字。
  List<Word> library() => [
    for (var i = 0; i < 30; i++) word('fresh$i', id: i),
    for (var i = 0; i < 5; i++)
      word(
        'wrong$i',
        id: 100 + i,
        wrong: i + 1,
        lastTest: DateTime(2026, 9, i + 1),
      ),
    for (var i = 0; i < 3; i++) word('known$i', id: 200 + i, right: 1),
  ];

  const rules = RulesConfig();

  test('題庫沒有已掌握的字時，配額讓給新字', () {
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(library(), now: now);

    expect(picked.length, 10);
    expect(picked.where((q) => q.isReview).length, 7);

    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('fresh')).length, 3);
    expect(words.where((w) => w.startsWith('wrong')).length, 5);
  });

  test('三種都夠的時候各拿各的配額：七待複習、兩新字、一已掌握', () {
    final pool = [
      for (var i = 0; i < 20; i++) word('fresh$i', id: i),
      for (var i = 0; i < 20; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
      for (var i = 0; i < 5; i++)
        word('done$i', id: 300 + i, right: 3, lastTest: DateTime(2026, 9, 1)),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(pool, now: now);

    final words = picked.map((q) => q.word.word).toList();
    expect(picked.length, 10);
    expect(words.where((w) => w.startsWith('wrong')).length, 7);
    expect(words.where((w) => w.startsWith('fresh')).length, 2);
    expect(words.where((w) => w.startsWith('done')).length, 1);
  });

  test('待複習只從離掌握還差最多次的前 30 名候選裡抽，不會選到後段的', () {
    // 50 個待複習字，rightNeededFor 只跟 wrong 成正比（right 都是 0），
    // 前 30 名門檻是 wrong >= 21（wrong=50..21 共 30 個）。
    // 但配額裡保留了一個名額給「最接近掌握」的字（wrong 最小的 wrong0），
    // 那個名額本來就該來自候選池外，所以只檢查扣掉它之後剩下的。
    final pool = [
      for (var i = 0; i < 50; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(7),
    ).pick(pool, now: now);

    final wrongCounts = picked
        .where((q) => q.isReview)
        .map((q) => q.word.wrong)
        .toList();
    expect(wrongCounts, contains(1), reason: '沒有保留最接近掌握的那個字（wrong=1）');
    final rest = wrongCounts.where((w) => w != 1);
    expect(rest.every((w) => w >= 21), isTrue, reason: '選到了候選前 30 名以外的字');
  });

  test('候選池大小可以在設定調，不是寫死 30', () {
    // 50 個待複習字，把候選池縮到 10：門檻變成 wrong >= 41（50..41 共 10 個）。
    // 同樣要扣掉保留給「最接近掌握」的那個名額再檢查。
    final pool = [
      for (var i = 0; i < 50; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
    ];
    final picked = QuestionPicker(
      rules: rules.copyWith(pendingCandidatePoolSize: 10),
      random: Random(7),
    ).pick(pool, now: now);

    final wrongCounts = picked
        .where((q) => q.isReview)
        .map((q) => q.word.wrong)
        .toList();
    expect(wrongCounts, contains(1), reason: '沒有保留最接近掌握的那個字（wrong=1）');
    final rest = wrongCounts.where((w) => w != 1);
    expect(rest.every((w) => w >= 41), isTrue, reason: '候選池大小沒有真的被設定值改掉');
  });

  test('待複習配額保留一個名額給最接近掌握的字', () {
    // wrong0（wrong=1）離掌握最近，rightNeededFor 最小，就算它排不進
    // 「離掌握最遠」的候選池（候選池只有 10 個，wrong0 排第 40 名），
    // 也該被保留的那個名額直接抓到。
    final pool = [
      for (var i = 0; i < 40; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
    ];
    final picked = QuestionPicker(
      rules: rules.copyWith(pendingCandidatePoolSize: 10),
      random: Random(3),
    ).pick(pool, now: now);

    expect(
      picked.any((q) => q.word.word == 'wrong0'),
      isTrue,
      reason: '最接近掌握的字（wrong=1）沒有被保留的名額抓到',
    );
  });

  test('待複習的候選池是隨機抽的，換個種子會抽到不同的字', () {
    final pool = [
      for (var i = 0; i < 40; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
    ];
    Set<String> pendingOf(int seed) =>
        QuestionPicker(rules: rules, random: Random(seed))
            .pick(pool, now: now)
            .where((q) => q.isReview)
            .map((q) => q.word.word)
            .toSet();

    expect(
      pendingOf(1),
      isNot(equals(pendingOf(2))),
      reason: '換個種子應該抽到不同的字，不然跟寫死前幾名沒兩樣',
    );
  });

  test('新字不夠時用待複習補滿', () {
    // 只有三個新字，待複習有八個。
    final pool = [
      for (var i = 0; i < 3; i++) word('fresh$i', id: i),
      for (var i = 0; i < 8; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(pool, now: now);

    expect(picked.length, rules.roundSize);
    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('fresh')).length, 3);
    expect(words.where((w) => w.startsWith('wrong')).length, 7);
  });

  test('答對過但也錯過的字仍然算待複習，會被抽到', () {
    // 這批字 right>=1 而且 wrong>0，四個池子的條件以前都不收它們。
    final pool = [
      word('fresh0', id: 1),
      for (var i = 0; i < 10; i++)
        word('shaky$i', id: 100 + i, right: 1, wrong: i + 1),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(pool, now: now);

    expect(picked.length, rules.roundSize);
    expect(
      picked.where((q) => q.word.word.startsWith('shaky')).length,
      9,
      reason: '錯過的字沒被當成待複習',
    );
  });

  test('待複習排在已確認的前面', () {
    final pool = [
      word('shaky0', id: 1, right: 1, wrong: 2),
      for (var i = 0; i < 10; i++)
        word('done$i', id: 100 + i, right: 3, lastTest: DateTime(2026, 9, 1)),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(pool, now: now);

    expect(
      picked.any((q) => q.word.word == 'shaky0'),
      isTrue,
      reason: '該先練的字被已確認的擠掉了',
    );
  });

  test('新字和待複習都用完時補已確認的字', () {
    // 一個新字、一個待複習，其餘都是已經確認會的。
    final pool = [
      word('fresh0', id: 1),
      word('wrong0', id: 2, wrong: 1),
      for (var i = 0; i < 10; i++)
        word('done$i', id: 100 + i, right: 3, lastTest: DateTime(2026, 9, 1)),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(pool, now: now);

    expect(picked.length, rules.roundSize, reason: '墊底的字沒補上來，一輪變少了');
    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('done')).length, 8);
  });

  test('待複習不夠時用新字補滿，題數不能少', () {
    final onlyFresh = [for (var i = 0; i < 30; i++) word('fresh$i', id: i)];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(onlyFresh, now: now);

    expect(picked.length, rules.roundSize, reason: '沒有回考的字，但新字要補滿');
  });

  test('關掉待複習就全部出新字', () {
    final picked = QuestionPicker(
      rules: rules.copyWith(pendingPerRound: 0),
      random: Random(1),
    ).pick(library(), now: now);

    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('wrong')).length, 0);
    expect(words.where((w) => w.startsWith('fresh')).length, 10);
  });

  test('只點選模式不出打字題', () {
    final picked = QuestionPicker(
      rules: rules.copyWith(quizStyle: QuizStyle.tapOnly),
      random: Random(1),
    ).pick(library(), now: now);

    expect(picked.every((q) => q.mode == QuizMode.tap), isTrue);
  });

  test('只打字模式每題都要打', () {
    final picked = QuestionPicker(
      rules: rules.copyWith(quizStyle: QuizStyle.typeOnly),
      random: Random(1),
    ).pick(library(), now: now);

    expect(picked.every((q) => q.mode == QuizMode.type), isTrue);
  });

  test('已掌握的回考題一律打字，就算是只點選模式', () {
    final pool = [
      for (var i = 0; i < 20; i++) word('fresh$i', id: i),
      for (var i = 0; i < 20; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
      for (var i = 0; i < 5; i++)
        word('done$i', id: 300 + i, right: 3, lastTest: DateTime(2026, 9, 1)),
    ];
    final picked = QuestionPicker(
      rules: rules.copyWith(quizStyle: QuizStyle.tapOnly),
      random: Random(1),
    ).pick(pool, now: now);

    final mastered = picked.where((q) => q.word.word.startsWith('done'));
    expect(mastered.length, 1);
    expect(mastered.every((q) => q.mode == QuizMode.type), isTrue);
    // 其餘的字還是照只點選模式，不要被已掌握的強制規則波及。
    final others = picked.where((q) => !q.word.word.startsWith('done'));
    expect(others.every((q) => q.mode == QuizMode.tap), isTrue);
  });

  test('偽裝模式關掉已掌握強制打字', () {
    final pool = [
      for (var i = 0; i < 20; i++) word('fresh$i', id: i),
      for (var i = 0; i < 20; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
      for (var i = 0; i < 5; i++)
        word('done$i', id: 300 + i, right: 3, lastTest: DateTime(2026, 9, 1)),
    ];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(pool, now: now, forceMasteredType: false);

    expect(picked.every((q) => q.mode == QuizMode.tap), isTrue);
  });

  test('混合模式時，已掌握的強制打字要算進打字題總額，不會超過設定值', () {
    final pool = [
      for (var i = 0; i < 20; i++) word('fresh$i', id: i),
      for (var i = 0; i < 20; i++) word('wrong$i', id: 100 + i, wrong: i + 1),
      for (var i = 0; i < 5; i++)
        word('done$i', id: 300 + i, right: 3, lastTest: DateTime(2026, 9, 1)),
    ];
    final picked = QuestionPicker(
      rules: rules.copyWith(quizStyle: QuizStyle.mixed, typeQuestions: 3),
      random: Random(1),
    ).pick(pool, now: now);

    expect(picked.where((q) => q.mode == QuizMode.type).length, 3);
    expect(
      picked
          .where((q) => q.word.word.startsWith('done'))
          .every((q) => q.mode == QuizMode.type),
      isTrue,
    );
  });

  group('句型', () {
    test('句型不會混進一般單字的三個池子', () {
      final pool = [
        for (var i = 0; i < 10; i++) word('fresh$i', id: i),
        sentence('I feel sick.', id: 900),
      ];
      final picked = QuestionPicker(
        // 關掉句型配額，句型字就不該用任何身分被抽到。
        rules: rules.copyWith(sentencePerRound: 0),
        random: Random(1),
      ).pick(pool, now: now);

      expect(
        picked.any((q) => q.word.word == 'I feel sick.'),
        isFalse,
        reason: '句型配額關掉時，句型字不該混進新字池被抽走',
      );
    });

    test('句型用自己的配額，不占新字名額', () {
      final pool = [
        for (var i = 0; i < 10; i++) word('fresh$i', id: i),
        sentence('I feel sick.', id: 900),
      ];
      final picked = QuestionPicker(
        rules: rules, // 預設 sentencePerRound: 1
        random: Random(1),
      ).pick(pool, now: now);

      expect(
        picked.where((q) => q.word.word == 'I feel sick.').length,
        1,
        reason: '有可用的句型時，配額裡該有一句',
      );
      expect(picked.length, rules.roundSize);
    });

    test('句型也照優先序：待複習排在新字前面', () {
      final pool = [
        for (var i = 0; i < 10; i++) word('fresh$i', id: i),
        sentence('I feel sick.', id: 900), // 新字（沒考過）
        sentence('Never mind.', id: 901, wrong: 1), // 待複習
      ];
      final picked = QuestionPicker(
        rules: rules,
        random: Random(1),
      ).pick(pool, now: now);

      final pickedSentences = picked
          .map((q) => q.word.word)
          .where((w) => w == 'I feel sick.' || w == 'Never mind.')
          .toList();
      expect(pickedSentences, ['Never mind.'], reason: '待複習的句子沒有被優先選到');
    });

    test('沒有句型可挑時，名額退回新字，題數不會變少', () {
      final pool = [for (var i = 0; i < 10; i++) word('fresh$i', id: i)];
      final picked = QuestionPicker(
        rules: rules, // 預設 sentencePerRound: 1，但這個題庫沒有句型字
        random: Random(1),
      ).pick(pool, now: now);

      expect(picked.length, rules.roundSize, reason: '句型抽不到，名額該讓新字補滿');
    });
  });
}

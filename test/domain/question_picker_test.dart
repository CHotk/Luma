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
  }) => Word(
    id: id,
    word: w,
    pos: 'n.',
    zh: '測試',
    grade: WordGrade.elementary,
    right: right,
    wrong: wrong,
    lastTest: lastTest,
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

  test('一輪十題：七個新字、兩個待複習、一個回考', () {
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(library(), now: now);

    expect(picked.length, 10);
    expect(picked.where((q) => q.isReview).length, 1);

    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('fresh')).length, 7);
    expect(words.where((w) => w.startsWith('wrong')).length, 2);
  });

  test('待複習挑錯最多次的', () {
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(library(), now: now);

    final pending = picked
        .map((q) => q.word)
        .where((w) => w.word.startsWith('wrong'))
        .map((w) => w.wrong)
        .toList();
    expect(pending, containsAll([5, 4]), reason: '錯最多次的兩個沒被排進來');
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

    expect(picked.length, rules.newPerRound);
    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('fresh')).length, 3);
    expect(words.where((w) => w.startsWith('wrong')).length, 6);
  });

  test('會過但也錯過的字不會被丟在中間沒人理', () {
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

    expect(picked.length, rules.newPerRound);
    expect(
      picked.where((q) => q.word.word.startsWith('shaky')).length,
      8,
      reason: '卡在中間的字還是沒被抽到',
    );
  });

  test('未確認的字排在已確認的前面', () {
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

    expect(picked.length, rules.newPerRound, reason: '墊底的字沒補上來，一輪變少了');
    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('done')).length, 7);
  });

  test('待複習不夠時用新字補滿，題數不能少', () {
    final onlyFresh = [for (var i = 0; i < 30; i++) word('fresh$i', id: i)];
    final picked = QuestionPicker(
      rules: rules,
      random: Random(1),
    ).pick(onlyFresh, now: now);

    expect(picked.length, rules.newPerRound, reason: '沒有回考的字，但新字要補滿');
  });

  test('關掉待複習就全部出新字', () {
    final picked = QuestionPicker(
      rules: rules.copyWith(pendingPerRound: 0),
      random: Random(1),
    ).pick(library(), now: now);

    final words = picked.map((q) => q.word.word).toList();
    expect(words.where((w) => w.startsWith('wrong')).length, 0);
    expect(words.where((w) => w.startsWith('fresh')).length, 9);
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
}

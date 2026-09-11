import 'dart:math';

import 'models/quiz.dart';
import 'models/word.dart';
import 'rules_config.dart';

/// 出題規則。
///
/// 一輪固定是「新字 ＋ 回考舊字」兩段，數量由 [RulesConfig] 決定。
/// 這個檔是純 Dart，不 import flutter，所以可以直接單元測試。
class QuestionPicker {
  QuestionPicker({required this.rules, Random? random})
    : _random = random ?? Random();

  final RulesConfig rules;
  final Random _random;

  /// 從整份單字庫挑出一輪的題目。
  ///
  /// [now] 由外面傳進來而不是自己抓，測試才能固定時間。
  List<QuizQuestion> pick(List<Word> all, {required DateTime now}) {
    final pending = _pickPending(all);
    // 待複習的字不夠時，缺的位置補新字，一輪的題數要固定。
    final freshWanted =
        rules.freshPerRound + (rules.pendingPerRound - pending.length);
    final fresh = _pickNew(all, freshWanted);
    final review = _pickReview(all);
    final words = [...fresh, ...pending, ...review];

    // 新字和回考混在一起再洗牌，不然使用者一眼就知道最後一題是回考。
    words.shuffle(_random);

    final typeIndexes = _chooseTypeIndexes(words.length);
    return [
      for (var i = 0; i < words.length; i++)
        QuizQuestion(
          word: words[i].word,
          mode: typeIndexes.contains(i) ? QuizMode.type : QuizMode.tap,
          isReview: words[i].isReview,
        ),
    ];
  }

  /// 沒考過的字。題庫順序本身是照字母排的，直接取會整輪都是同一個字母，
  /// 所以先洗牌再取。
  List<({Word word, bool isReview})> _pickNew(List<Word> all, int count) {
    if (count <= 0) return const [];
    final pool = all.where((w) => w.isUntested).toList()..shuffle(_random);
    return pool.take(count).map((w) => (word: w, isReview: false)).toList();
  }

  /// 待複習：答錯過而且到現在還沒答對過的字。
  ///
  /// 這是使用者最需要的那批字。錯最多次的先回來，同樣次數就挑最久沒考的，
  /// 不然同一個字會一直霸著位置，其他錯過的字永遠輪不到。
  List<({Word word, bool isReview})> _pickPending(List<Word> all) {
    if (rules.pendingPerRound <= 0) return const [];
    final pool = all.where((w) => w.right == 0 && w.wrong > 0).toList()
      ..sort((a, b) {
        if (a.wrong != b.wrong) return b.wrong.compareTo(a.wrong);
        final at = a.lastTest;
        final bt = b.lastTest;
        if (at == null && bt == null) return 0;
        if (at == null) return -1;
        if (bt == null) return 1;
        return at.compareTo(bt);
      });
    return pool
        .take(rules.pendingPerRound)
        .map((w) => (word: w, isReview: false))
        .toList();
  }

  /// 回考的舊字：答對過但還沒到門檻，而且從沒答錯過。
  /// 挑最久沒被考的優先，這樣每個字都輪得到。
  List<({Word word, bool isReview})> _pickReview(List<Word> all) {
    final pool =
        all
            .where(
              (w) =>
                  w.right >= 1 && w.wrong == 0 && w.right < rules.confirmRight,
            )
            .toList()
          ..sort((a, b) {
            final at = a.lastTest;
            final bt = b.lastTest;
            if (at == null && bt == null) return 0;
            if (at == null) return -1; // 沒紀錄的最優先
            if (bt == null) return 1;
            return at.compareTo(bt);
          });
    return pool
        .take(rules.reviewPerRound)
        .map((w) => (word: w, isReview: true))
        .toList();
  }

  /// 決定哪幾題要打字。隨機散開，不要固定在最後幾題。
  /// 要出幾題由 [RulesConfig.effectiveTypeQuestions] 決定，這裡不判斷模式。
  Set<int> _chooseTypeIndexes(int questionCount) {
    final wanted = min(rules.effectiveTypeQuestions, questionCount);
    if (wanted <= 0) return const {};
    final indexes = List.generate(questionCount, (i) => i)..shuffle(_random);
    return indexes.take(wanted).toSet();
  }
}

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
    // 一輪固定由三種來源組成，各有配額：待複習、新字、已掌握。
    // 哪一種不夠就往下補，順序是「最需要練的先補」，
    // 所以一輪的題數永遠是滿的。
    //
    // 四個池子都用 [Word.statusWith] 判斷，不要在這裡自己寫條件，
    // 不然狀態的定義改了這裡會默默地跟不上。
    final target = rules.roundSize;
    final pendingPool = _pendingPool(all);
    final freshPool = _freshPool(all);
    final masteredPool = _confirmedPool(all);

    // 先各拿各的配額。
    final pending = pendingPool.take(rules.pendingPerRound).toList();
    final mastered = masteredPool.take(rules.masteredPerRound).toList();
    final fresh = freshPool
        .take(target - pending.length - mastered.length)
        .toList();

    // 有人不夠就往下補，順序照「最需要練的先補」：
    // 待複習 → 新字 → 已掌握。
    int shortfall() => target - pending.length - mastered.length - fresh.length;

    if (shortfall() > 0) {
      pending.addAll(pendingPool.skip(pending.length).take(shortfall()));
    }
    if (shortfall() > 0) {
      fresh.addAll(freshPool.skip(fresh.length).take(shortfall()));
    }
    if (shortfall() > 0) {
      mastered.addAll(masteredPool.skip(mastered.length).take(shortfall()));
    }

    final words = [
      for (final w in fresh) (word: w, isReview: false),
      // 待複習和已掌握都算複習，結果頁才分得出新字與舊字。
      for (final w in [...pending, ...mastered]) (word: w, isReview: true),
    ];

    // 新字和複習混在一起再洗牌，不然使用者一眼就知道最後一題是複習。
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
  List<Word> _freshPool(List<Word> all) =>
      all.where((w) => w.statusWith(rules) == WordStatus.untested).toList()
        ..shuffle(_random);

  /// 待複習：**錯過就算**，跟後來有沒有答對無關。
  ///
  /// 使用者 2026-09-11 明確講過這條。以前寫成「還沒答對過」，
  /// 結果 right=1 wrong=3 那種字兩邊都不收，永遠不會再出現。
  ///
  /// 錯最多次的先回來，同樣次數就挑最久沒考的，
  /// 不然同一個字會一直霸著位置，其他錯過的字永遠輪不到。
  List<Word> _pendingPool(List<Word> all) =>
      all.where((w) => w.statusWith(rules) == WordStatus.pending).toList()
        ..sort((a, b) {
          if (a.wrong != b.wrong) return b.wrong.compareTo(a.wrong);
          final at = a.lastTest;
          final bt = b.lastTest;
          if (at == null && bt == null) return 0;
          if (at == null) return -1;
          if (bt == null) return 1;
          return at.compareTo(bt);
        });

  /// 已經確認會的字，最久沒考的排前面。
  /// 只有在新字和待複習都用完時才會動到這批。
  List<Word> _confirmedPool(List<Word> all) =>
      all.where((w) => w.statusWith(rules) == WordStatus.confirmed).toList()
        ..sort((a, b) {
          final at = a.lastTest;
          final bt = b.lastTest;
          if (at == null && bt == null) return 0;
          if (at == null) return -1;
          if (bt == null) return 1;
          return at.compareTo(bt);
        });

  /// 決定哪幾題要打字。隨機散開，不要固定在最後幾題。
  /// 要出幾題由 [RulesConfig.effectiveTypeQuestions] 決定，這裡不判斷模式。
  Set<int> _chooseTypeIndexes(int questionCount) {
    final wanted = min(rules.effectiveTypeQuestions, questionCount);
    if (wanted <= 0) return const {};
    final indexes = List.generate(questionCount, (i) => i)..shuffle(_random);
    return indexes.take(wanted).toSet();
  }
}

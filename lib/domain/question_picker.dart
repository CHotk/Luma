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
  ///
  /// [forceMasteredType] 已掌握的回考題一律用中翻英打字，不管 `quizStyle` 是什麼：
  /// 掌握不代表拼得出來，回考只給看得懂沒有用，拼錯了也要留下打了什麼。
  /// 偽裝模式要關掉這個（傳 false），跳中文輸入法在辦公室很顯眼。
  List<QuizQuestion> pick(
    List<Word> all, {
    required DateTime now,
    bool forceMasteredType = true,
  }) {
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

    // 句型是獨立的第四個池子，配額從新字挪過來（使用者 2026-09-16 決定），
    // 不跟一般單字混在待複習/新字/已掌握三個池子裡——句型的 Word 本來就
    // 被排除在那三個池子外（見 _pendingPool/_freshPool/_confirmedPool），
    // 這裡才是句型真正出場的地方。
    final sentences = _pickSentences(all, rules.sentencePerRound);

    // 待複習配額裡先保留一個名額給「最接近掌握」的字：
    // pendingPool 排序是離掌握最遠在前面，所以最接近的就是排最後那個
    // （rightNeededFor 最小，但還沒到 0，不然狀態就不是待複習了）。
    // 使用者 2026-09-15 決定的：不是每次都啃最遠的，也給快完成的字
    // 一個直接送過門檻的機會。
    final pending = <Word>[];
    if (rules.pendingPerRound > 0 && pendingPool.isNotEmpty) {
      pending.add(pendingPool.last);
    }

    // 剩下的名額才是原本的規則：從「最需要練」的候選池（大小可在設定調）
    // 裡隨機抽，同樣需要練的字换著出。排除掉已經保留給「最接近掌握」的那個，
    // 不然可能抽兩次同一個字。
    final reserved = pending.toSet();
    final pendingCandidates =
        pendingPool
            .where((w) => !reserved.contains(w))
            .take(rules.pendingCandidatePoolSize)
            .toList()
          ..shuffle(_random);
    pending.addAll(pendingCandidates.take(rules.pendingPerRound - pending.length));

    final mastered = masteredPool.take(rules.masteredPerRound).toList();
    final fresh = freshPool
        .take(target - pending.length - mastered.length - sentences.length)
        .toList();

    // 有人不夠就往下補，順序照「最需要練的先補」：
    // 待複習 → 新字 → 已掌握。句型不夠（例如句型庫被抽完）不特別處理，
    // 上面算 fresh 時已經把 sentences 的缺額算進去了，新字會自動多補一題，
    // 這個名額本來就是從新字挪過去的，缺額退回去很自然。
    int shortfall() =>
        target - pending.length - mastered.length - fresh.length - sentences.length;

    if (shortfall() > 0) {
      // 補額不用再隨機，直接照優先順序拿剩下最需要練的，
      // 這裡要的是「補滿題數」不是「換花樣」。
      final used = pending.toSet();
      final rest = pendingPool.where((w) => !used.contains(w));
      pending.addAll(rest.take(shortfall()));
    }
    if (shortfall() > 0) {
      fresh.addAll(freshPool.skip(fresh.length).take(shortfall()));
    }
    if (shortfall() > 0) {
      mastered.addAll(masteredPool.skip(mastered.length).take(shortfall()));
    }

    final words = [
      for (final w in fresh)
        (word: w, isReview: false, forceType: false, isMastered: false),
      // 待複習和已掌握都算複習，結果頁才分得出新字與舊字，
      // 但已掌握的還要多標一個 isMastered，結果頁才能三種來源分開顯示。
      for (final w in pending)
        (word: w, isReview: true, forceType: false, isMastered: false),
      for (final w in mastered)
        (
          word: w,
          isReview: true,
          forceType: forceMasteredType,
          isMastered: true,
        ),
      // 句型沿用一樣的規則：已掌握的句子回考也強制打字，
      // 看得懂一句話不代表打得出來。
      for (final s in sentences)
        (
          word: s.word,
          isReview: s.isReview,
          forceType: s.isMastered && forceMasteredType,
          isMastered: s.isMastered,
        ),
    ];

    // 新字和複習混在一起再洗牌，不然使用者一眼就知道最後一題是複習。
    words.shuffle(_random);

    // 已經被強制打字的題，不用再從隨機名額裡挑，也不用再占一個名額。
    final eligible = [
      for (var i = 0; i < words.length; i++)
        if (!words[i].forceType) i,
    ];
    final forcedCount = words.length - eligible.length;
    final typeIndexes = _chooseTypeIndexes(eligible, forcedCount: forcedCount);
    return [
      for (var i = 0; i < words.length; i++)
        QuizQuestion(
          word: words[i].word,
          mode: words[i].forceType || typeIndexes.contains(i)
              ? QuizMode.type
              : QuizMode.tap,
          isReview: words[i].isReview,
          isMasteredReview: words[i].isMastered,
        ),
    ];
  }

  /// 是不是句型（一整句英文），不是一般單字。句型有自己獨立的四個池子，
  /// 不跟一般單字的待複習/新字/已掌握混在一起，所以三個主池子都要排除它。
  bool _isSentence(Word w) => w.tags.contains(sentenceTag);

  /// 沒考過的字。題庫順序本身是照字母排的，直接取會整輪都是同一個字母，
  /// 所以先洗牌再取。
  List<Word> _freshPool(List<Word> all) =>
      all
          .where((w) => !_isSentence(w) && w.statusWith(rules) == WordStatus.untested)
          .toList()
        ..shuffle(_random);

  /// 待複習：**錯過就算**，跟後來有沒有答對無關。
  ///
  /// 使用者 2026-09-11 明確講過這條。以前寫成「還沒答對過」，
  /// 結果 right=1 wrong=3 那種字兩邊都不收，永遠不會再出現。
  ///
  /// 排序看 [Word.rightNeededFor]，不是看單純的錯幾次：
  /// 那個算法已經把「錯過的字要答對 recoveryRatio 倍」跟
  /// 「沒錯過但還沒到 confirmRight」兩種情況打平成同一把尺，
  /// 離掌握還差最多次答對的排最前面。同樣差距的挑最久沒考的，
  /// 不然同一個字會一直霸著候選池的前段。
  List<Word> _pendingPool(List<Word> all) =>
      all
          .where((w) => !_isSentence(w) && w.statusWith(rules) == WordStatus.pending)
          .toList()
        ..sort(_byRightNeededDesc);

  /// 已經確認會的字，最久沒考的排前面。
  /// 只有在新字和待複習都用完時才會動到這批。
  List<Word> _confirmedPool(List<Word> all) =>
      all
          .where((w) => !_isSentence(w) && w.statusWith(rules) == WordStatus.confirmed)
          .toList()
        ..sort(_byOldestLastTestFirst);

  /// 句型版的待複習池，規則跟 [_pendingPool] 一模一樣，只是只看句型。
  List<Word> _sentencePendingPool(List<Word> all) =>
      all
          .where((w) => _isSentence(w) && w.statusWith(rules) == WordStatus.pending)
          .toList()
        ..sort(_byRightNeededDesc);

  /// 句型版的新字池，規則跟 [_freshPool] 一模一樣，只是只看句型。
  List<Word> _sentenceFreshPool(List<Word> all) =>
      all
          .where((w) => _isSentence(w) && w.statusWith(rules) == WordStatus.untested)
          .toList()
        ..shuffle(_random);

  /// 句型版的已掌握池，規則跟 [_confirmedPool] 一模一樣，只是只看句型。
  List<Word> _sentenceConfirmedPool(List<Word> all) =>
      all
          .where((w) => _isSentence(w) && w.statusWith(rules) == WordStatus.confirmed)
          .toList()
        ..sort(_byOldestLastTestFirst);

  /// 挑句型：跟主要三池同一套優先序「待複習 → 新字 → 已掌握」，
  /// 只是資料來源是句型專屬的三個池子。回傳連同來源狀態一起標好，
  /// 讓 [pick] 知道這句該算 isReview 還是 isMastered。
  List<({Word word, bool isReview, bool isMastered})> _pickSentences(
    List<Word> all,
    int count,
  ) {
    if (count <= 0) return const [];

    final picked = <({Word word, bool isReview, bool isMastered})>[];
    final used = <Word>{};

    void takeFrom(
      List<Word> pool, {
      required bool isReview,
      required bool isMastered,
    }) {
      for (final w in pool) {
        if (picked.length >= count) return;
        if (!used.add(w)) continue;
        picked.add((word: w, isReview: isReview, isMastered: isMastered));
      }
    }

    takeFrom(_sentencePendingPool(all), isReview: true, isMastered: false);
    if (picked.length < count) {
      takeFrom(_sentenceFreshPool(all), isReview: false, isMastered: false);
    }
    if (picked.length < count) {
      takeFrom(_sentenceConfirmedPool(all), isReview: true, isMastered: true);
    }
    return picked;
  }

  int _byRightNeededDesc(Word a, Word b) {
    final da = a.rightNeededFor(rules);
    final db = b.rightNeededFor(rules);
    if (da != db) return db.compareTo(da);
    return _byOldestLastTestFirst(a, b);
  }

  int _byOldestLastTestFirst(Word a, Word b) {
    final at = a.lastTest;
    final bt = b.lastTest;
    if (at == null && bt == null) return 0;
    if (at == null) return -1;
    if (bt == null) return 1;
    return at.compareTo(bt);
  }

  /// 決定哪幾題要打字。隨機散開，不要固定在最後幾題。
  /// 要出幾題由 [RulesConfig.effectiveTypeQuestions] 決定，這裡不判斷模式，
  /// 但已掌握的字被強制打字後，剩下的名額只從 [eligible]（其餘題目）裡挑，
  /// 而且名額本身要先扣掉 [forcedCount]，不然一輪的打字題總數會超過設定值。
  Set<int> _chooseTypeIndexes(List<int> eligible, {required int forcedCount}) {
    final wanted = min(
      max(rules.effectiveTypeQuestions - forcedCount, 0),
      eligible.length,
    );
    if (wanted <= 0) return const {};
    final shuffled = [...eligible]..shuffle(_random);
    return shuffled.take(wanted).toSet();
  }
}

/// 50 音考試和詞彙考試的題庫資料。
class ExamQuestionData {
  /// 50 音考試題目（a ~ n，共 20 題）。
  static const List<(String romaji, String kana)> kanaQuestions = [
    ('a', 'あ'),
    ('i', 'い'),
    ('u', 'う'),
    ('e', 'え'),
    ('o', 'お'),
    ('ka', 'か'),
    ('ki', 'き'),
    ('ku', 'く'),
    ('ke', 'け'),
    ('ko', 'こ'),
    ('sa', 'さ'),
    ('shi', 'し'),
    ('su', 'す'),
    ('se', 'せ'),
    ('so', 'そ'),
    ('ta', 'た'),
    ('chi', 'ち'),
    ('tsu', 'つ'),
    ('te', 'て'),
    ('to', 'と'),
  ];

  /// 詞彙考試題目（漢字 → 平假名）。
  /// TODO: 實裝詞彙模式時擴展這個列表。
  static const List<(String kanji, String hiragana)> vocabQuestions = [
    ('猫', 'ねこ'),
    ('犬', 'いぬ'),
    ('魚', 'さかな'),
    ('水', 'みず'),
    ('火', 'ひ'),
    ('木', 'き'),
    ('山', 'やま'),
    ('川', 'かわ'),
    ('日', 'ひ'),
    ('月', 'つき'),
  ];

  /// 取得隨機排列的 50 音題目（洗牌）。
  static List<(String romaji, String kana)> getShuffledKanaQuestions({
    int count = 20,
  }) {
    final questions = [...kanaQuestions];
    questions.shuffle();
    return questions.take(count).toList();
  }

  /// 取得隨機排列的詞彙題目（洗牌）。
  static List<(String kanji, String hiragana)> getShuffledVocabQuestions({
    int count = 10,
  }) {
    final questions = [...vocabQuestions];
    questions.shuffle();
    return questions.take(count).toList();
  }
}

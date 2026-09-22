/// 一題的內容：羅馬字、要寫出來的假名、這個假名是不是片假名。
///
/// [isKatakana] 存在的理由：題目畫面只顯示羅馬字，使用者光看羅馬字
/// 分不出這題要寫平假名還是片假名（兩種字體的羅馬字拼法完全一樣），
/// 要靠這個欄位在畫面上明確標出「請寫平假名／片假名」，還要配不同
/// 顏色，不然容易看錯題目（2026-09-21 使用者要求）。
typedef ExamQuestion = (String romaji, String kana, bool isKatakana);

/// 50 音考試和詞彙考試的題庫資料。
class ExamQuestionData {
  /// 50 音考試題目（a ~ n，共 20 題），固定題庫沒有選範圍時的預設，
  /// 全部平假名。
  static const List<ExamQuestion> kanaQuestions = [
    ('a', 'あ', false),
    ('i', 'い', false),
    ('u', 'う', false),
    ('e', 'え', false),
    ('o', 'お', false),
    ('ka', 'か', false),
    ('ki', 'き', false),
    ('ku', 'く', false),
    ('ke', 'け', false),
    ('ko', 'こ', false),
    ('sa', 'さ', false),
    ('shi', 'し', false),
    ('su', 'す', false),
    ('se', 'せ', false),
    ('so', 'そ', false),
    ('ta', 'た', false),
    ('chi', 'ち', false),
    ('tsu', 'つ', false),
    ('te', 'て', false),
    ('to', 'と', false),
  ];

  /// 詞彙考試題目（漢字 → 平假名）。[isKatakana] 對詞彙模式沒有意義，
  /// 固定 false，只是為了跟 [kanaQuestions] 共用同一個型別。
  /// TODO: 實裝詞彙模式時擴展這個列表。
  static const List<ExamQuestion> vocabQuestions = [
    ('猫', 'ねこ', false),
    ('犬', 'いぬ', false),
    ('魚', 'さかな', false),
    ('水', 'みず', false),
    ('火', 'ひ', false),
    ('木', 'き', false),
    ('山', 'やま', false),
    ('川', 'かわ', false),
    ('日', 'ひ', false),
    ('月', 'つき', false),
  ];

  /// 取得隨機排列的 50 音題目（洗牌）。
  static List<ExamQuestion> getShuffledKanaQuestions({int count = 20}) {
    final questions = [...kanaQuestions];
    questions.shuffle();
    return questions.take(count).toList();
  }

  /// 取得隨機排列的詞彙題目（洗牌）。
  static List<ExamQuestion> getShuffledVocabQuestions({int count = 10}) {
    final questions = [...vocabQuestions];
    questions.shuffle();
    return questions.take(count).toList();
  }
}

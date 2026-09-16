/// 拼字題的判定。
///
/// 幾條規則是使用者決定的，不要因為「好像太嚴」就自己放寬，
/// 也不要因為「好像太鬆」就自己收緊：
///   1. 不管大小寫。Weather 和 weather 都算對。
///   2. 複數算錯。打 socks 以外的 sock 就是錯，因為題目考的是那個字本身。
///   3. a 和 an 視為不同的字。它們本來就是兩個不同的詞。
///   4. 標點符號不算數（使用者 2026-09-16 決定，句型上線後才加的規則）。
///      考的是「打不打得出這句話」，不是「標點符號背得多熟」，
///      You're 打成 Youre、句尾漏打句號都不算錯。
///
/// 換句話說：把前後空白去掉、大小寫拉平、非英數字元拿掉。
/// 不做字根還原也不做複數還原，也**不做大小寫例外**——
/// 曾經考慮過「月份這種專有名詞要求開頭大寫」，但句子開頭本來就會大寫，
/// 程式沒辦法只憑存的字串分辨那個大寫是「文法規定要大寫」還是「剛好在
/// 句首」，勉強做只會多一個要人工標記的欄位，為了這種次要重點不值得，
/// 已經跟使用者確認過維持現狀不加例外。
abstract final class SpellJudge {
  static bool isCorrect({required String input, required String answer}) {
    return normalize(input) == normalize(answer);
  }

  /// 判定前的正規化：去頭尾空白、拉平大小寫、拿掉標點符號，
  /// 多個空白收成一個。不做字根還原也不做複數還原。
  static String normalize(String raw) {
    final lettersOnly = stripPunctuation(raw.trim().toLowerCase());
    return lettersOnly.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 拿掉標點符號，但不動大小寫——給畫面用的，題卡上的空格列跟輸入框
  /// 都要用同一套「什麼算標點符號」的定義，不然畫面跟判定會對不起來。
  /// 只留英數字跟空白，句號、逗號、撇號這些都算標點符號。
  static String stripPunctuation(String raw) =>
      raw.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');

  /// 打的字數已經跟答案一樣長，可以直接判定，不用等人按送出。
  ///
  /// 比的是正規化之後的長度，不是原始長度：句子的標點符號不算數，
  /// 用原始長度比會導致少打標點符號的人永遠打不滿字數，自動判定不會觸發。
  static bool isComplete({required String input, required String answer}) =>
      normalize(input).length >= normalize(answer).length;
}

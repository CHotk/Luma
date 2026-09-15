/// 拼字題的判定。
///
/// 三條規則是使用者 2026-09-11 明確決定的，不要因為「好像太嚴」就自己放寬：
///   1. 不管大小寫。Weather 和 weather 都算對。
///   2. 複數算錯。打 socks 以外的 sock 就是錯，因為題目考的是那個字本身。
///   3. a 和 an 視為不同的字。它們本來就是兩個不同的詞。
///
/// 換句話說：只把前後空白去掉、把大小寫拉平，其餘一律逐字比對。
abstract final class SpellJudge {
  static bool isCorrect({required String input, required String answer}) {
    return normalize(input) == normalize(answer);
  }

  /// 判定前的正規化。只做兩件事，不做字根還原也不做複數還原。
  static String normalize(String raw) => raw.trim().toLowerCase();

  /// 打的字數已經跟答案一樣長，可以直接判定，不用等人按送出。
  static bool isComplete({required String input, required String answer}) =>
      input.trim().length >= answer.length;
}

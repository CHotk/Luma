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

  /// 提示用的遮罩，例如 weather 會變成 "w _ _ _ _ _ _"。
  /// 只露出第一個字母，露太多就等於送分。
  static String mask(String answer) {
    if (answer.isEmpty) return '';
    final rest = List.filled(answer.length - 1, '_').join(' ');
    return rest.isEmpty ? answer[0] : '${answer[0]} $rest';
  }
}

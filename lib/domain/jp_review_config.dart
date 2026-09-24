/// 日文假名手寫練習的簡化複習排程參數。
///
/// 跟英文軌道的 [RulesConfig] 同一個精神，只是簡化很多：假名手寫沒有
/// 題型、沒有打字對錯可判，只看「今天寫了幾個字」跟「多久沒複習就
/// 退回待複習」這兩件事（使用者 2026-09-17 決定要有這套排程，日文
/// 首頁的圓環跟「下一輪」清單才有真數字可以顯示，不是編出來的）。
class JpReviewConfig {
  const JpReviewConfig({
    this.dailyKanaTarget = 5,
    this.dailyMinutesTarget = 10,
    this.masteryPracticeCount = 3,
    this.reviewStaleDays = 7,
  });

  /// 今天要練幾個字才算「今天的份量做完」，首頁進度環看這個。
  final int dailyKanaTarget;

  /// 目標練習分鐘數，進度環下方那行參考用，不是限制條件。
  final int dailyMinutesTarget;

  /// 純手寫（不算輔助描摹）要練到幾次才算「已掌握」這個字。
  final int masteryPracticeCount;

  /// 已掌握的字超過幾天沒再碰，就退回待複習——複習本來就該隔一段時間
  /// 才有意義，不是練到門檻就永遠不用管了。
  final int reviewStaleDays;

  factory JpReviewConfig.fromJson(Map<String, dynamic> json) {
    const d = JpReviewConfig();
    return JpReviewConfig(
      dailyKanaTarget: json['jpDailyKanaTarget'] as int? ?? d.dailyKanaTarget,
      dailyMinutesTarget:
          json['jpDailyMinutesTarget'] as int? ?? d.dailyMinutesTarget,
      masteryPracticeCount:
          json['jpMasteryPracticeCount'] as int? ?? d.masteryPracticeCount,
      reviewStaleDays: json['jpReviewStaleDays'] as int? ?? d.reviewStaleDays,
    );
  }
}

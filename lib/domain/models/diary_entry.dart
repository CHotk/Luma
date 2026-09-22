/// 日記的一筆紀錄。走「極簡打卡」路線（設計稿 04 定案）：心情＋一行
/// 文字，不是長文日記，`id` 存檔當下的微秒時間戳，跟手寫練習／考試
/// 紀錄同一套慣例。
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.mood,
    required this.text,
    required this.savedAt,
    this.weather = '',
  });

  final String id;
  final String mood;
  final String text;
  final DateTime savedAt;

  /// 天氣，選填——2026-09-22 才加的欄位，舊紀錄沒有這欄，讀不到就當
  /// 空字串（沒選），不是拿一個假天氣硬套上去。
  final String weather;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mood': mood,
    'text': text,
    'savedAt': savedAt.toIso8601String(),
    'weather': weather,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'] as String,
    mood: json['mood'] as String,
    text: json['text'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
    weather: json['weather'] as String? ?? '',
  );
}

/// 打卡可選的五種心情，跟設計稿 04 一致，順序就是好→差。
const diaryMoods = ['😄', '🙂', '😐', '😔', '😢'];

/// 打卡可選的天氣（2026-09-22 使用者要求）。
const diaryWeathers = ['晴', '陰', '雨', '熱', '冷', '普通'];

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

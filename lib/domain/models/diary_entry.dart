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
    this.temperature = '',
    this.deletedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? savedAt;

  final String id;
  final String mood;
  final String text;
  final DateTime savedAt;

  /// 墓碑標記（soft delete）——刪除不是真的把這筆從清單拿掉，是填上
  /// 現在的時間戳記，null 代表沒被刪除。多裝置同步要靠這個才知道
  /// 「這筆是被刻意刪除的」，不是「本來就沒出現過」——單純物理刪除的
  /// 話，合併時看不出差別，下次同步會把已刪除的紀錄復活
  /// （2026-09-23 使用者推導出這個問題、確認要用墓碑標記，見
  /// `data/cloud/r2_sync_service.dart` 的說明）。合併規則是「刪除永遠
  /// 贏」：任一邊看過這筆的刪除標記，合併結果就是刪除，不比較時間新舊
  /// ——簡單但有取捨：刪除後又在別的裝置編輯同一篇，編輯不會生效
  /// （使用者 2026-09-23 確認接受這個取捨，對個人一兩台裝置的用途
  /// 夠用，不做更複雜的時間戳記比較）。
  final DateTime? deletedAt;

  /// 天氣（晴／陰／雨），選填——2026-09-22 才加的欄位，舊紀錄沒有這欄，
  /// 讀不到就當空字串（沒選），不是拿一個假天氣硬套上去。
  final String weather;

  /// 冷熱感受（熱／普通／冷），選填，跟 [weather] 是兩個獨立的屬性——
  /// 陰晴雨是天氣現象，冷熱普通是體感，不是同一件事，不能塞進同一排
  /// 選項（2026-09-22 使用者糾正：一開始誤把六個選項當同一屬性）。
  final String temperature;

  /// 最後一次「內容有變」的時間——新增時預設等於 [savedAt]，編輯／刪除
  /// 都會蓋成當下（見 [DiaryRepository.update]／[copyWithDeleted]）。
  /// 多裝置同步合併非刪除紀錄時靠這個比新舊（見 `seed_merge.dart` 的
  /// [_overlay] 說明）——原本「本機永遠贏」在裝置 A 編輯、裝置 B 同步
  /// 抓回來時會被裝置 B 沒改過的舊版蓋掉，編輯等於沒同步到
  /// （2026-09-23 使用者發現這個問題）；刪除仍然「永遠贏」，不受這個
  /// 時間戳影響。
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mood': mood,
    'text': text,
    'savedAt': savedAt.toIso8601String(),
    'weather': weather,
    'temperature': temperature,
    'deletedAt': deletedAt?.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'] as String,
    mood: json['mood'] as String,
    text: json['text'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
    weather: json['weather'] as String? ?? '',
    temperature: json['temperature'] as String? ?? '',
    deletedAt: json['deletedAt'] == null
        ? null
        : DateTime.parse(json['deletedAt'] as String),
    // 舊紀錄（存檔當下這欄位還不存在）沒有這欄，落回 savedAt——當作
    // 「存檔之後沒再編輯過」，不是硬塞一個假的最新時間。
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
  );

  DiaryEntry copyWithDeleted() {
    final now = DateTime.now();
    return DiaryEntry(
      id: id,
      mood: mood,
      text: text,
      savedAt: savedAt,
      weather: weather,
      temperature: temperature,
      deletedAt: now,
      updatedAt: now,
    );
  }

  /// 編輯存檔時呼叫，把 [updatedAt] 蓋成現在，其餘欄位照 `this`（呼叫端
  /// 已經把新的心情／文字放進這個 entry 了）——見
  /// [DiaryRepository.update]。
  DiaryEntry copyWithTouched() => DiaryEntry(
    id: id,
    mood: mood,
    text: text,
    savedAt: savedAt,
    weather: weather,
    temperature: temperature,
    deletedAt: deletedAt,
    updatedAt: DateTime.now(),
  );
}

/// 打卡可選的五種心情，跟設計稿 04 一致，順序就是好→差。
const diaryMoods = ['😄', '🙂', '😐', '😔', '😢'];

/// 打卡可選的天氣現象（2026-09-22 使用者要求）。
const diaryWeathers = ['晴', '陰', '雨'];

/// 打卡可選的冷熱感受，跟 [diaryWeathers] 分開一排（2026-09-22 使用者
/// 要求：陰晴雨／冷熱普通不是同一屬性）。
const diaryTemperatures = ['熱', '普通', '冷'];

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

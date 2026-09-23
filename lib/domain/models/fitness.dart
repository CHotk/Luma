import 'package:flutter/material.dart';

/// 健身打卡的運動類型——不開放自訂輸入：這個功能的重點是降低
/// 「今天有沒有動」的記錄門檻（見設計稿 02 打卡日曆式），開放自由輸入
/// 使用者又要多想一步，違背這個功能本來的目的（2026-09-23 使用者選定
/// 02 打卡日曆式為主頁、04 統計儀表板式當「統計」按鈕點開的子頁）。
/// 原本只有四個籠統分類，2026-09-23 使用者要求加四個具體項目
/// （跑步／伏地挺身／仰臥起坐／徒手深蹲）——跟前四個籠統分類會有點
/// 概念重疊（例如跑步本來就算有氧），但使用者要的就是能直接選具體
/// 項目，不用自己換算成「這算哪一種籠統分類」，尊重使用者的選擇。
enum FitnessType {
  strength,
  cardio,
  yoga,
  stretch,
  running,
  pushup,
  situp,
  squat,
}

extension FitnessTypeX on FitnessType {
  String get label => switch (this) {
    FitnessType.strength => '重訓',
    FitnessType.cardio => '有氧',
    FitnessType.yoga => '瑜珈',
    FitnessType.stretch => '伸展',
    FitnessType.running => '跑步',
    FitnessType.pushup => '伏地挺身',
    FitnessType.situp => '仰臥起坐',
    FitnessType.squat => '徒手深蹲',
  };

  String get emoji => switch (this) {
    FitnessType.strength => '🏋️',
    FitnessType.cardio => '🏃',
    FitnessType.yoga => '🧘',
    FitnessType.stretch => '🤸',
    FitnessType.running => '🏃‍♂️',
    FitnessType.pushup => '💪',
    FitnessType.situp => '🧎',
    FitnessType.squat => '🦵',
  };

  /// 跟設計稿 04 統計儀表板式的甜甜圈圖同一組配色邏輯延伸，八色對八種
  /// 類型固定綁死，跟 YT 頻道追蹤分類色盤（`ytCategoryColors`）同一組
  /// 色票，全專案的「固定分類色」統一同一套色感。
  Color get color => switch (this) {
    FitnessType.strength => const Color(0xFF5FC9A8),
    FitnessType.cardio => const Color(0xFF6AA9E0),
    FitnessType.yoga => const Color(0xFFC98FE0),
    FitnessType.stretch => const Color(0xFFE0A94E),
    FitnessType.running => const Color(0xFFE07A7A),
    FitnessType.pushup => const Color(0xFF5FB8C9),
    FitnessType.situp => const Color(0xFFE069A0),
    FitnessType.squat => const Color(0xFF8592E0),
  };

  String get storageValue => name;

  static FitnessType fromStorage(String value) => FitnessType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => FitnessType.strength,
  );
}

/// 一筆打卡紀錄。[date] 只取年月日（當天，不含時分秒）——月曆判斷
/// 「這天有沒有練」只看日期，[loggedAt] 才是真正打卡的時間點，兩者
/// 分開存：之後如果要做「回填昨天/前天」（跟日記簽到卡同樣的構想），
/// [date] 才有意義獨立於「今天」之外。
class FitnessEntry {
  const FitnessEntry({
    required this.id,
    required this.date,
    required this.type,
    this.durationMinutes,
    required this.loggedAt,
  });

  final String id;
  final DateTime date;
  final FitnessType type;

  /// 選填，這次先不強制要求輸入時長——打卡當下越少欄位越好
  /// （設計稿 05 極簡快速打卡式的理由，跟 02 一起套用）。
  final int? durationMinutes;
  final DateTime loggedAt;

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': dayOnly(date).toIso8601String(),
    'type': type.storageValue,
    'durationMinutes': durationMinutes,
    'loggedAt': loggedAt.toIso8601String(),
  };

  factory FitnessEntry.fromJson(Map<String, dynamic> json) => FitnessEntry(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    type: FitnessTypeX.fromStorage(json['type'] as String),
    durationMinutes: json['durationMinutes'] as int?,
    loggedAt: DateTime.parse(json['loggedAt'] as String),
  );
}

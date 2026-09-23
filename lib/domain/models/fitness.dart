import 'package:flutter/material.dart';

/// 健身打卡的運動類型——固定四種，不開放自訂：這個功能的重點是降低
/// 「今天有沒有動」的記錄門檻（見設計稿 02 打卡日曆式），選項一多
/// 使用者又要多想一步，違背這個功能本來的目的
/// （2026-09-23 使用者選定 02 打卡日曆式為主頁、04 統計儀表板式當
/// 「統計」按鈕點開的子頁）。
enum FitnessType { strength, cardio, yoga, stretch }

extension FitnessTypeX on FitnessType {
  String get label => switch (this) {
    FitnessType.strength => '重訓',
    FitnessType.cardio => '有氧',
    FitnessType.yoga => '瑜珈',
    FitnessType.stretch => '伸展',
  };

  String get emoji => switch (this) {
    FitnessType.strength => '🏋️',
    FitnessType.cardio => '🏃',
    FitnessType.yoga => '🧘',
    FitnessType.stretch => '🤸',
  };

  /// 跟設計稿 04 統計儀表板式的甜甜圈圖同一組配色，四色對四種類型
  /// 固定綁死，不用另外挑色。
  Color get color => switch (this) {
    FitnessType.strength => const Color(0xFF5FC9A8),
    FitnessType.cardio => const Color(0xFF6AA9E0),
    FitnessType.yoga => const Color(0xFFC98FE0),
    FitnessType.stretch => const Color(0xFFE0A94E),
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

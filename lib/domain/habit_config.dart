import 'package:flutter/material.dart';

/// 「多久做一次」型紀錄的設定（2026-09-24）：看盤（看虛擬貨幣價格）、抽菸、
/// 喝酒共用同一套畫面與資料結構（距離上次計時器、冷靜按鈕、月曆、最近
/// 紀錄、統計），差別只在文字、原因選項、顏色跟存放的 key，全部集中在這裡。
///
/// [storageKey]／[cloudKey] 一旦用過就不能改——本機資料跟雲端檔案都靠它
/// 找得到（看盤那組沿用最早的名字 `crypto_watch`）。
class HabitConfig {
  const HabitConfig({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.storageKey,
    required this.cloudKey,
    required this.verb,
    required this.unit,
    required this.sinceLabel,
    required this.recordLabel,
    required this.cravingQuestion,
    required this.cooldownHint,
    required this.cooldownButton,
    required this.reasonPrompt,
    required this.reasonStatsTitle,
    required this.emptyHint,
    required this.reasons,
  });

  /// 路由用的識別字：`/habit/<id>`。
  final String id;

  /// 功能名稱（頁面標題、首頁格子、選單）。
  final String title;
  final IconData icon;
  final Color color;
  final String storageKey;
  final String cloudKey;

  /// 動詞（看／抽／喝）跟量詞（次／根／杯），組「今天已抽 3 根」用。
  final String verb;
  final String unit;

  final String sinceLabel;
  final String recordLabel;
  final String cravingQuestion;
  final String cooldownHint;
  final String cooldownButton;
  final String reasonPrompt;
  final String reasonStatsTitle;
  final String emptyHint;

  /// 選填的觸發原因（順序就是選單順序）。
  final List<String> reasons;

  String get route => '/habit/$id';
  String get statsRoute => '/habit/$id/stats';
}

const cryptoWatchHabit = HabitConfig(
  id: 'crypto',
  title: '看盤記錄',
  icon: Icons.candlestick_chart_outlined,
  color: Color(0xFFF7931A),
  storageKey: 'crypto_watch.entries.v1',
  cloudKey: 'crypto_watch.json',
  verb: '看',
  unit: '次',
  sinceLabel: '距離上次看價格',
  recordLabel: '我剛看了價格（重新計時）',
  cravingQuestion: '想看了嗎？',
  cooldownHint: '先深呼吸，10 分鐘後還想看再看。',
  cooldownButton: '先冷靜 10 分鐘',
  reasonPrompt: '為什麼想看？（選填）',
  reasonStatsTitle: '為什麼看？',
  emptyHint: '還沒有紀錄，看完價格按下面的按鈕記一筆',
  reasons: ['焦慮', '無聊', '例行', '睡前', '其他'],
);

const smokingHabit = HabitConfig(
  id: 'smoking',
  title: '抽菸記錄',
  icon: Icons.smoking_rooms_outlined,
  color: Color(0xFFB0B7C3),
  storageKey: 'smoking.entries.v1',
  cloudKey: 'smoking.json',
  verb: '抽',
  unit: '根',
  sinceLabel: '距離上次抽菸',
  recordLabel: '我剛抽了一根（重新計時）',
  cravingQuestion: '想抽了嗎？',
  cooldownHint: '先深呼吸、喝杯水，10 分鐘後還想抽再抽。',
  cooldownButton: '先忍 10 分鐘',
  reasonPrompt: '為什麼想抽？（選填）',
  reasonStatsTitle: '為什麼抽？',
  emptyHint: '還沒有紀錄，抽完按下面的按鈕記一筆',
  reasons: ['壓力', '無聊', '飯後', '社交', '習慣', '其他'],
);

const drinkingHabit = HabitConfig(
  id: 'drinking',
  title: '喝酒記錄',
  icon: Icons.local_bar_outlined,
  color: Color(0xFFE0607E),
  storageKey: 'drinking.entries.v1',
  cloudKey: 'drinking.json',
  verb: '喝',
  unit: '杯',
  sinceLabel: '距離上次喝酒',
  recordLabel: '我剛喝了一杯（重新計時）',
  cravingQuestion: '想喝了嗎？',
  cooldownHint: '先喝杯水，10 分鐘後還想喝再喝。',
  cooldownButton: '先忍 10 分鐘',
  reasonPrompt: '為什麼想喝？（選填）',
  reasonStatsTitle: '為什麼喝？',
  emptyHint: '還沒有紀錄，喝完按下面的按鈕記一筆',
  reasons: ['社交', '壓力', '無聊', '慶祝', '睡前', '其他'],
);

const allHabits = [cryptoWatchHabit, smokingHabit, drinkingHabit];

HabitConfig? habitConfigById(String id) {
  for (final h in allHabits) {
    if (h.id == id) return h;
  }
  return null;
}

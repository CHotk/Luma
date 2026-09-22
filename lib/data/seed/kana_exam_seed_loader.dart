import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/kana_exam.dart';

/// 讀 `assets/data/kana_exam.json`：考試紀錄快照，跟
/// [loadKanaPracticeSeed]（見 `kana_practice_seed_loader.dart`）同一個
/// 用途——讓在別的裝置／瀏覽器匯出的考試紀錄，重新部署後能合併回每個
/// 裝置自己的 localStorage（2026-09-22 使用者要求：考試紀錄也要有這套
/// 機制）。
///
/// 使用者還沒把匯出的檔案放進去、或者内容還是空陣列，都算正常——讀
/// 不到、格式壞掉就當沒有快照資料，不讓例外往上炸把整個考試紀錄頁
/// 弄壞（跟 `kana_practice_seed_loader.dart` 同一套保險政策）。
Future<List<KanaExamEntry>> loadKanaExamSeed() async {
  try {
    final raw = await rootBundle.loadString('assets/data/kana_exam.json');
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(KanaExamEntry.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}

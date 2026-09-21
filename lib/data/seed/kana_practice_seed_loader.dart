import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/kana_practice.dart';

/// 讀 `assets/data/kana_practice.json`：手寫練習紀錄快照，讓在別的
/// 裝置／瀏覽器匯出的紀錄，重新部署後能合併回每個裝置自己的
/// localStorage（2026-09-18 使用者要求）。全部筆數都會保留，不砍
/// 上限（2026-09-21 使用者要求：每一筆手寫紀錄都要能帶著走）。
///
/// 使用者還沒把匯出的檔案放進去、或者内容還是空陣列，都算正常——
/// 不是每個人都會用這個功能，讀不到、格式壞掉就當沒有快照資料，
/// 不讓例外往上炸把整個練習紀錄頁弄壞（跟 `app_defaults_loader.dart`
/// 讀失敗退回預設值同一套保險政策）。
Future<List<KanaPracticeEntry>> loadKanaPracticeSeed() async {
  try {
    final raw = await rootBundle.loadString('assets/data/kana_practice.json');
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(KanaPracticeEntry.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}

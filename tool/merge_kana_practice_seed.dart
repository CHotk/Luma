// 把匯出的手寫練習紀錄（history 頁「匯出紀錄」按的那份，檔名長得像
// lume-kana-practice-20260918.json）併進專案唯一的種子檔案
// assets/data/kana_practice.json，併完就把匯出檔案刪掉——不然資料夾
// 裡會堆一堆各自的匯出檔，之後只留一份統一的（2026-09-18 使用者
// 要求）。App 端讀種子檔案的地方見
// lib/data/seed/kana_practice_seed_loader.dart。
//
// 用法：
//   dart run tool/merge_kana_practice_seed.dart <匯出檔路徑...> [--limit=N]
//
// 規則：
//   - 用 id 判斷重複，匯入檔案裡的版本蓋掉種子檔案裡同 id 的舊版本
//     （跟 KanaPracticeRepository.mergeSeed 同一套「新的為準」邏輯）。
//   - 依 savedAt 排序，只留最新的 N 筆（預設 20）——種子檔案是給別的
//     裝置補資料用的「最近快照」，不是要備份全部歷史；本機
//     localStorage 自己會留全部，種子檔案沒必要跟著無限長大。
import 'dart:convert';
import 'dart:io';

const _seedPath = 'assets/data/kana_practice.json';
const _defaultLimit = 20;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      '用法：dart run tool/merge_kana_practice_seed.dart <匯出檔路徑...> [--limit=N]',
    );
    exit(1);
  }

  var limit = _defaultLimit;
  final importPaths = <String>[];
  for (final a in args) {
    if (a.startsWith('--limit=')) {
      limit = int.tryParse(a.substring('--limit='.length)) ?? _defaultLimit;
    } else {
      importPaths.add(a);
    }
  }

  final seedFile = File(_seedPath);
  final existing = seedFile.existsSync()
      ? (jsonDecode(seedFile.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];

  final byId = {for (final e in existing) e['id'] as String: e};

  var importedFiles = 0;
  for (final path in importPaths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('找不到檔案，跳過：$path');
      continue;
    }
    final incoming = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    for (final e in incoming) {
      // 匯入檔案為準，蓋掉種子檔案裡同 id 的舊版本。
      byId[e['id'] as String] = e;
    }
    importedFiles++;
  }

  final merged = byId.values.toList()
    ..sort(
      (a, b) => (a['savedAt'] as String).compareTo(b['savedAt'] as String),
    );
  final kept = merged.length > limit
      ? merged.sublist(merged.length - limit)
      : merged;

  seedFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(kept));

  for (final path in importPaths) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  stdout.writeln(
    '併完：$_seedPath 現在有 ${kept.length} 筆'
    '（原本 ${existing.length} 筆，併入 $importedFiles 個檔案，'
    '上限 $limit 筆）。',
  );
}

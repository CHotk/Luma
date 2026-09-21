// 把匯出的手寫練習紀錄（history 頁「匯出紀錄」按的那份，檔名長得像
// lume-kana-practice-20260918.json）併進專案唯一的手寫紀錄快照檔案
// assets/data/kana_practice.json，併完就把匯出檔案刪掉——不然資料夾
// 裡會堆一堆各自的匯出檔，之後只留一份統一的（2026-09-18 使用者
// 要求）。App 端讀快照檔案的地方見
// lib/data/seed/kana_practice_seed_loader.dart。
//
// 用法：
//   dart run tool/merge_kana_practice_seed.dart <匯出檔路徑...>
//
// 規則：
//   - 用 id 判斷重複，匯入檔案裡的版本蓋掉快照檔案裡同 id 的舊版本
//     （跟 KanaPracticeRepository.mergeSeed 同一套「新的為準」邏輯）。
//   - 依 savedAt 排序，全部保留，不砍筆數上限——這份快照就是要讓
//     每一筆手寫紀錄都能帶著走，砍掉舊的等於練習成果憑空消失
//     （2026-09-21 使用者要求：不要設上限，確保每一筆都有保存到）。
import 'dart:convert';
import 'dart:io';

const _seedPath = 'assets/data/kana_practice.json';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法：dart run tool/merge_kana_practice_seed.dart <匯出檔路徑...>');
    exit(1);
  }

  final seedFile = File(_seedPath);
  final existing = seedFile.existsSync()
      ? (jsonDecode(seedFile.readAsStringSync()) as List)
            .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];

  final byId = {for (final e in existing) e['id'] as String: e};

  var importedFiles = 0;
  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('找不到檔案，跳過：$path');
      continue;
    }
    final incoming = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    for (final e in incoming) {
      // 匯入檔案為準，蓋掉快照檔案裡同 id 的舊版本。
      byId[e['id'] as String] = e;
    }
    importedFiles++;
  }

  final merged = byId.values.toList()
    ..sort(
      (a, b) => (a['savedAt'] as String).compareTo(b['savedAt'] as String),
    );

  seedFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(merged),
  );

  for (final path in args) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  stdout.writeln(
    '併完：$_seedPath 現在有 ${merged.length} 筆'
    '（原本 ${existing.length} 筆，併入 $importedFiles 個檔案）。',
  );
}

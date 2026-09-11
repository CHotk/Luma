import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/word.dart';
import 'seed_source.dart';

/// 把打包在 App 裡的題庫與既有紀錄讀進來。
///
/// 兩個來源：
///   assets/data/seed-words.txt  題庫，還沒考過的候選字
///   assets/data/words.txt       使用者已經考過的字，帶著對錯次數
///
/// 欄位都用「兩個以上空白」分隔，開頭是 # 的是註解或表頭。
/// 第一行的 `# seed-version: N` 是題庫版本，加了新字就要往上加。
class WordSeedLoader implements SeedSource {
  static final _separator = RegExp(r' {2,}');
  static final _versionLine = RegExp(r'^#\s*seed-version:\s*(\d+)');

  @override
  Future<int> version() async {
    final raw = await rootBundle.loadString('assets/data/seed-words.txt');
    for (final line in raw.split('\n').take(5)) {
      final match = _versionLine.firstMatch(line.trim());
      if (match != null) return int.parse(match.group(1)!);
    }
    // 沒寫版本就當第一版，避免舊檔讓整個升級流程卡住。
    return 1;
  }

  @override
  Future<List<Word>> seedWords() async {
    final raw = await rootBundle.loadString('assets/data/seed-words.txt');
    final words = <Word>[];
    for (final line in _rows(raw)) {
      final cols = line.split(_separator);
      if (cols.length < 5) continue;
      words.add(
        Word(
          id: int.tryParse(cols[0]) ?? words.length + 1,
          word: cols[1],
          pos: cols[2],
          zh: cols[3],
          level: WordLevel.parse(cols[4]),
        ),
      );
    }
    return words;
  }

  @override
  Future<List<Word>> initialImport() async {
    final seeds = await seedWords();
    final history = await _readExisting();

    // 用小寫當鍵比對，避免 Monday 這種大寫字重複收錄。
    final byWord = <String, Word>{};
    for (final w in seeds) {
      byWord[w.word.toLowerCase()] = w;
    }

    // 已經考過的字覆蓋掉題庫那筆，成績才不會被洗掉。
    // 題庫沒有但考過的字也要留著，那是使用者實際碰過的字。
    var nextId = seeds.length;
    for (final entry in history.entries) {
      final existing = byWord[entry.key];
      byWord[entry.key] = existing != null
          ? existing.copyWith(
              right: entry.value.right,
              wrong: entry.value.wrong,
              lastTest: entry.value.lastTest,
            )
          : Word(
              id: ++nextId,
              word: entry.value.word,
              pos: entry.value.pos,
              zh: entry.value.zh,
              level: WordLevel.elementary,
              right: entry.value.right,
              wrong: entry.value.wrong,
              lastTest: entry.value.lastTest,
            );
    }

    return byWord.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// 既有紀錄：no / word / pos / zh / example / added / right / wrong / last_test
  Future<Map<String, _Existing>> _readExisting() async {
    final raw = await rootBundle.loadString('assets/data/words.txt');
    final result = <String, _Existing>{};
    for (final line in _rows(raw)) {
      final cols = line.split(_separator);
      if (cols.length < 8) continue;
      final word = cols[1];
      result[word.toLowerCase()] = _Existing(
        word: word,
        pos: cols[2],
        zh: cols[3],
        right: int.tryParse(cols[6]) ?? 0,
        wrong: int.tryParse(cols[7]) ?? 0,
        lastTest: cols.length > 8 ? DateTime.tryParse(cols[8]) : null,
      );
    }
    return result;
  }

  /// 去掉註解與空行，順便修掉行尾空白。
  Iterable<String> _rows(String raw) => raw
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty && !l.startsWith('#'));
}

/// words.txt 的一列。只是搬運用，不對外露出。
class _Existing {
  const _Existing({
    required this.word,
    required this.pos,
    required this.zh,
    required this.right,
    required this.wrong,
    this.lastTest,
  });

  final String word;
  final String pos;
  final String zh;
  final int right;
  final int wrong;
  final DateTime? lastTest;
}

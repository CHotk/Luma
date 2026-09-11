import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/word.dart';

/// 把打包在 App 裡的題庫與既有紀錄讀進來。
///
/// 只在第一次開啟時用。之後資料以本機儲存為準，不再回頭讀這些檔。
///
/// 兩個來源：
///   assets/data/seed-words.txt  題庫，還沒考過的候選字
///   assets/data/words.txt       使用者已經考過的字，帶著對錯次數
///
/// 兩個檔的欄位都用「兩個以上空白」分隔，開頭是 # 的是表頭。
class WordSeedLoader {
  static final _separator = RegExp(r' {2,}');

  Future<List<Word>> load() async {
    final seeds = await _readSeed();
    final history = await _readExisting();

    // 用小寫當鍵比對，避免 Monday 這種大寫字重複收錄。
    final byWord = <String, Word>{};
    for (final w in seeds) {
      byWord[w.word.toLowerCase()] = w;
    }

    // 已經考過的字覆蓋掉題庫那筆，成績才不會被洗掉。
    // 題庫沒有但考過的字（例如當初隨口問的）也要留著。
    var nextId = seeds.length;
    for (final entry in history.entries) {
      final existing = byWord[entry.key];
      if (existing != null) {
        byWord[entry.key] = existing.copyWith(
          right: entry.value.right,
          wrong: entry.value.wrong,
          lastTest: entry.value.lastTest,
        );
      } else {
        byWord[entry.key] = Word(
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
    }

    return byWord.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// 題庫：no / word / pos / zh / level
  Future<List<Word>> _readSeed() async {
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

  /// 去掉表頭與空行，順便修掉行尾空白。
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

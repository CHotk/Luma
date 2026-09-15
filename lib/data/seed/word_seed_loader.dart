import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/history.dart';
import '../../domain/models/word.dart';
import 'seed_source.dart';

/// 把打包在 App 裡的題庫與既有紀錄讀進來。
///
/// 三個來源：
///   assets/data/seed-words.txt    單字題庫，還沒考過的候選字
///   assets/data/seed-phrases.txt  高頻固定搭配，跟單字題庫同一套欄位規則，
///                                 讀完直接併進同一個池子，出題、篩選都跟單字一視同仁
///   assets/data/words.txt         使用者已經考過的字，帶著對錯次數
///
/// 欄位都用「兩個以上空白」分隔，開頭是 # 的是註解或表頭。
/// 第一行的 `# seed-version: N` 是題庫版本，加了新字就要往上加。
class WordSeedLoader implements SeedSource {
  static final _separator = RegExp(r' {2,}');

  /// 每次從 En 資料夾重新複製檔案進 assets 就要 +1。
  /// 忘了加，App 就不會同步，然後你會以為程式壞了。
  @override
  int get bundleVersion => 18;

  Future<List<Word>> _seedWords() async {
    final words = <Word>[];
    await _loadWordFile('assets/data/seed-words.txt', words);
    await _loadWordFile('assets/data/seed-phrases.txt', words);
    return words;
  }

  /// 讀一份「單字題庫格式」的檔案，剖析結果直接接在 [words] 後面。
  /// 單字題庫和固定搭配用同一個剖析器，欄位規則要保持一致。
  Future<void> _loadWordFile(String asset, List<Word> words) async {
    final raw = await rootBundle.loadString(asset);
    for (final line in _rows(raw)) {
      final cols = line.split(_separator);
      if (cols.length < 5) continue;
      words.add(
        Word(
          id: int.tryParse(cols[0]) ?? words.length + 1,
          word: cols[1],
          pos: cols[2],
          zh: cols[3],
          grade: WordGrade.parse(cols[4]),
          topic: cols.length > 5 ? WordTopic.parse(cols[5]) : WordTopic.none,
          senseCount: cols.length > 6
              ? WordSenseCount.parse(cols[6])
              : WordSenseCount.none,
          tags: cols.length > 7 ? Word.parseTags(cols[7]) : const [],
        ),
      );
    }
  }

  @override
  Future<List<Word>> bundle() async {
    final seeds = await _seedWords();
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
              example: entry.value.example,
              added: entry.value.added,
              right: entry.value.right,
              wrong: entry.value.wrong,
              lastTest: entry.value.lastTest,
              // 題庫跟 words.txt 都有標籤時是合併不是誰蓋過誰，
              // 不然題庫標的分類考過一次就會被洗掉。
              tags: {...existing.tags, ...entry.value.tags}.toList(),
            )
          : Word(
              id: ++nextId,
              word: entry.value.word,
              pos: entry.value.pos,
              zh: entry.value.zh,
              // words.txt 沒有階段欄位，考過但題庫沒有的字先當國小。
              grade: WordGrade.elementary,
              example: entry.value.example,
              added: entry.value.added,
              right: entry.value.right,
              wrong: entry.value.wrong,
              lastTest: entry.value.lastTest,
              tags: entry.value.tags,
            );
    }

    return byWord.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// 測驗紀錄：date / round / word / result [/ mode / input / seconds]
  ///
  /// 前四欄是必要的：round 長得像 R12，result 只有 O 和 X。
  /// 後三欄是後來才加的，舊資料沒有也讀得起來：
  ///   mode    tap 或 type
  ///   input   打字題實際打了什麼，點選題寫 -
  ///   seconds 想了幾秒
  ///
  /// 早期的紀錄沒有時分也沒有秒數，那是資料本身就沒有，不是 bug。
  @override
  Future<List<HistoryEntry>> bundleHistory() async {
    final raw = await rootBundle.loadString('assets/data/history.txt');
    final entries = <HistoryEntry>[];
    for (final line in _rows(raw)) {
      final cols = line.split(_separator);
      if (cols.length < 4) continue;
      final at = DateTime.tryParse(cols[0]);
      final round = int.tryParse(cols[1].replaceFirst('R', ''));
      if (at == null || round == null) continue;

      final input = cols.length > 5 ? cols[5].trim() : '';
      entries.add(
        HistoryEntry(
          round: round,
          word: cols[2],
          correct: cols[3].trim() == 'O',
          at: at,
          typed: cols.length > 4 && cols[4].trim() == 'type',
          input: input == '-' ? '' : input,
          seconds: cols.length > 6 ? int.tryParse(cols[6].trim()) ?? 0 : 0,
        ),
      );
    }
    return entries;
  }

  /// 既有紀錄：no / word / pos / zh / example / added / right / wrong / last_test / tags
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
        example: cols[4],
        added: DateTime.tryParse(cols[5]),
        right: int.tryParse(cols[6]) ?? 0,
        wrong: int.tryParse(cols[7]) ?? 0,
        lastTest: cols.length > 8 ? DateTime.tryParse(cols[8]) : null,
        tags: cols.length > 9 ? Word.parseTags(cols[9]) : const [],
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
    required this.example,
    required this.right,
    required this.wrong,
    this.added,
    this.lastTest,
    this.tags = const [],
  });

  final String word;
  final String pos;
  final String zh;
  final String example;
  final DateTime? added;
  final int right;
  final int wrong;
  final DateTime? lastTest;
  final List<String> tags;
}

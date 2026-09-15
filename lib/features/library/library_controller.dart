import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/word.dart';
import '../../domain/rules_config.dart';
import '../../domain/scoring.dart';
import '../notes/notes_controller.dart';

/// 搜尋字串。英文、中文、標籤都能搜。
final libraryQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// 狀態篩選。null 代表不篩。
final libraryFilterProvider = StateProvider.autoDispose<WordStatus?>(
  (ref) => null,
);

/// 類別篩選。null 代表不篩。跟狀態是「且」的關係，兩個可以同時生效。
final libraryTopicProvider = StateProvider.autoDispose<WordTopic?>(
  (ref) => null,
);

/// 詞義豐富度篩選。null 代表不篩。跟狀態、類別都是「且」的關係。
final librarySenseProvider = StateProvider.autoDispose<WordSenseCount?>(
  (ref) => null,
);

/// 排序方式。整份篩選結果一起排，不會先照狀態分組再各排各的
/// （使用者 2026-09-15 決定：選了排序方式就是要整個單字庫照那個排，
/// 不是待複習一群、新字一群、已掌握一群，個別排好之後再接在一起）。
/// 如果只想看某個狀態，用篩選列的狀態篩選，那是獨立的另一件事。
enum LibrarySort {
  /// 練習次數（答對＋答錯）多的排前面。使用者 2026-09-15 決定的新預設：
  /// 練習次數多代表這個字被回考很多次，比題庫原本的編號更值得先看到。
  attempts('練習次數多到少'),

  /// 照題庫原本的編號排，這是改預設之前的排法，保留給想找回舊排序的人。
  id('題庫編號'),

  /// 權重高到低，用 [Word.masteryWeight] 算：權重高代表掌握得紮實，
  /// 排最前面（使用者 2026-09-15 決定，不是把最差的排前面）。
  /// 錯過的字要答對次數達到答錯次數的 `recoveryRatio` 倍才算打平，
  /// 不是單純比錯的次數，這樣不同路線的字才排得進同一把尺。
  weighted('權重高到低'),

  /// 單字字母數，短到長。
  length('單字長度（短到長）');

  const LibrarySort(this.label);
  final String label;
}

/// 排序方式。預設是練習次數多到少，不是題庫編號。
final librarySortProvider = StateProvider.autoDispose<LibrarySort>(
  (ref) => LibrarySort.attempts,
);

/// 單字庫畫面要的資料。
class LibraryData {
  const LibraryData({
    required this.words,
    required this.counts,
    required this.topicCounts,
    required this.senseCounts,
    required this.traps,
    required this.rules,
  });

  /// 篩選與搜尋之後的結果。
  final List<Word> words;

  /// 三種狀態各有幾個字。這是全庫的數量，不受搜尋影響，
  /// 不然篩選鈕上的數字會跟著搜尋跳動，很難用。
  final Map<WordStatus, int> counts;

  /// 每個類別各有幾個字，給下拉選單顯示。
  final Map<WordTopic, int> topicCounts;

  /// 每個詞義豐富度各有幾個字，給下拉選單顯示。
  final Map<WordSenseCount, int> senseCounts;

  /// 地雷字對應到第幾則筆記。鍵是小寫的單字。
  final Map<String, String> traps;

  final RulesConfig rules;
}

final libraryProvider = FutureProvider.autoDispose<LibraryData>((ref) async {
  ref.watch(dataRevisionProvider);
  final all = await ref.watch(wordRepositoryProvider).loadAll();
  final rules = await ref.watch(settingsRepositoryProvider).loadRules();
  final query = ref.watch(libraryQueryProvider).trim();
  final filter = ref.watch(libraryFilterProvider);
  final topic = ref.watch(libraryTopicProvider);
  final sense = ref.watch(librarySenseProvider);
  final sortBy = ref.watch(librarySortProvider);
  final traps = await ref.watch(trapWordsProvider.future);

  final counts = Scoring.countByStatus(all, rules);

  // 有幾個字被分過類，決定要不要顯示類別下拉。
  final topicCounts = <WordTopic, int>{};
  final senseCounts = <WordSenseCount, int>{};
  for (final w in all) {
    topicCounts[w.topic] = (topicCounts[w.topic] ?? 0) + 1;
    senseCounts[w.senseCount] = (senseCounts[w.senseCount] ?? 0) + 1;
  }

  final lower = query.toLowerCase();
  final filtered = all.where((w) {
    if (filter != null && w.statusWith(rules) != filter) {
      return false;
    }
    // 狀態、類別、詞義豐富度是「且」的關係：選了都要同時符合。
    if (topic != null && w.topic != topic) return false;
    if (sense != null && w.senseCount != sense) return false;
    if (query.isEmpty) return true;
    if (w.word.toLowerCase().contains(lower) || w.zh.contains(query)) {
      return true;
    }
    return w.tags.any((t) => t.toLowerCase().contains(lower));
  }).toList();

  // 整份篩選結果一起排，不先照狀態分組。想只看某個狀態就用狀態篩選，
  // 那是另一件獨立的事，不該跟排序方式綁在一起。
  filtered.sort((a, b) {
    switch (sortBy) {
      case LibrarySort.attempts:
        final ta = a.right + a.wrong;
        final tb = b.right + b.wrong;
        if (ta != tb) return tb.compareTo(ta);
        return a.id.compareTo(b.id);
      case LibrarySort.id:
        return a.id.compareTo(b.id);
      case LibrarySort.weighted:
        // 權重越高代表掌握得越紮實，降序：最好的排最前面。
        final wa = a.masteryWeight(rules);
        final wb = b.masteryWeight(rules);
        if (wa != wb) return wb.compareTo(wa);
        return a.id.compareTo(b.id);
      case LibrarySort.length:
        final la = a.word.length;
        final lb = b.word.length;
        if (la != lb) return la.compareTo(lb);
        return a.id.compareTo(b.id);
    }
  });

  return LibraryData(
    words: filtered,
    counts: counts,
    topicCounts: topicCounts,
    senseCounts: senseCounts,
    traps: traps,
    rules: rules,
  );
});

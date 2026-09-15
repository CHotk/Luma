import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/history.dart';
import '../../domain/models/word.dart';
import '../../domain/rules_config.dart';
import '../notes/notes_controller.dart';

/// 單字詳情要的東西：字本身、它的作答歷史、目前的過關門檻。
class WordDetail {
  const WordDetail({
    required this.word,
    required this.history,
    required this.rules,
    this.trapNote,
    this.senseNote,
  });

  final Word word;

  /// 這個字被考過的每一次，新的排前面。
  final List<HistoryEntry> history;

  /// 這個字是地雷字的話，對應到第幾則筆記。
  final String? trapNote;

  /// 這個字有義項解析的話，對應到第幾則筆記。
  final String? senseNote;

  final RulesConfig rules;
}

/// 依單字查詳情。family 的參數是單字本身，不是 id，
/// 因為網址上放單字比較看得懂，分享出去也知道是哪個字。
final wordDetailProvider = FutureProvider.autoDispose
    .family<WordDetail, String>((ref, word) async {
      ref.watch(dataRevisionProvider);
      final all = await ref.watch(wordRepositoryProvider).loadAll();
      final rules = await ref.watch(settingsRepositoryProvider).loadRules();
      final history = await ref.watch(historyRepositoryProvider).forWord(word);
      final traps = await ref.watch(trapWordsProvider.future);
      final senses = await ref.watch(senseWordsProvider.future);

      final key = word.toLowerCase();
      final found = all.firstWhere(
        (w) => w.word.toLowerCase() == key,
        orElse: () => throw StateError('單字庫裡沒有 $word'),
      );

      return WordDetail(
        word: found,
        history: history,
        rules: rules,
        trapNote: traps[key],
        senseNote: senses[key],
      );
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed/note_loader.dart';
import '../../domain/models/usage_note.dart';

/// 用法地雷是唯讀的，讀一次放著就好，不用 autoDispose。
final usageNotesProvider = FutureProvider<List<UsageNote>>(
  (ref) => NoteLoader().load(),
);

/// 哪些字是地雷字，以及它對應到第幾則筆記。鍵是小寫的單字。
///
/// 資料來源就是每則筆記結尾的「相關單字」，不另外維護一份名單。
/// 這樣只要寫了筆記，那幾個字就自動被標成地雷，不會忘記同步。
final trapWordsProvider = FutureProvider<Map<String, String>>((ref) async {
  final notes = await ref.watch(usageNotesProvider.future);
  final map = <String, String>{};
  for (final note in notes) {
    for (final word in note.relatedWords) {
      // 同一個字出現在多則裡就留第一則，通常那則講得最完整。
      map.putIfAbsent(word.toLowerCase(), () => note.no);
    }
  }
  return map;
});

/// 依編號取一則。找不到就回 null，讓畫面自己處理。
final usageNoteProvider = FutureProvider.autoDispose.family<UsageNote?, String>(
  (ref, no) async {
    final all = await ref.watch(usageNotesProvider.future);
    for (final note in all) {
      if (note.no == no) return note;
    }
    return null;
  },
);

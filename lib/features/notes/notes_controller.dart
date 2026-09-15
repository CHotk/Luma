import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed/note_loader.dart';
import '../../domain/models/note_collection.dart';
import '../../domain/models/usage_note.dart';

/// 目前在看哪一本筆記。
final noteCollectionProvider = StateProvider<NoteCollection>(
  (ref) => NoteCollection.traps,
);

/// 某一本筆記的全部內容。唯讀，讀一次放著就好，不用 autoDispose。
final notesProvider = FutureProvider.family<List<UsageNote>, NoteCollection>(
  (ref, collection) => NoteLoader(collection.asset).load(),
);

/// 依編號取一則。找不到就回 null，讓畫面自己處理。
final noteProvider = FutureProvider.autoDispose
    .family<UsageNote?, ({NoteCollection collection, String no})>((
      ref,
      key,
    ) async {
      final all = await ref.watch(notesProvider(key.collection).future);
      for (final note in all) {
        if (note.no == key.no) return note;
      }
      return null;
    });

/// 哪些字是地雷字，以及它對應到第幾則筆記。鍵是小寫的單字。
///
/// 資料來源就是每則筆記結尾的「相關單字」，不另外維護一份名單。
/// 這樣只要寫了筆記，那幾個字就自動被標上，不會忘記同步。
///
/// 只看用法地雷那一本。近義字是「選哪個比較好」，不是「講了會出事」，
/// 兩者混在同一個標記裡會讓警告失去意義。
final trapWordsProvider = FutureProvider<Map<String, String>>((ref) async {
  final notes = await ref.watch(notesProvider(NoteCollection.traps).future);
  final map = <String, String>{};
  for (final note in notes) {
    for (final word in note.relatedWords) {
      // 同一個字出現在多則裡就留第一則，通常那則講得最完整。
      map.putIfAbsent(word.toLowerCase(), () => note.no);
    }
  }
  return map;
});

/// 哪些字有義項解析，以及對應到第幾則筆記。鍵是小寫的單字。
///
/// 跟 [trapWordsProvider] 同一套做法：資料來源是義項解析那本筆記結尾的
/// 「相關單字」，不另外維護名單。這本是一則一個字，不會有一則對到多個字。
final senseWordsProvider = FutureProvider<Map<String, String>>((ref) async {
  final notes = await ref.watch(notesProvider(NoteCollection.senses).future);
  final map = <String, String>{};
  for (final note in notes) {
    for (final word in note.relatedWords) {
      map.putIfAbsent(word.toLowerCase(), () => note.no);
    }
  }
  return map;
});

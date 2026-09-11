import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed/note_loader.dart';
import '../../domain/models/usage_note.dart';

/// 用法地雷是唯讀的，讀一次放著就好，不用 autoDispose。
final usageNotesProvider = FutureProvider<List<UsageNote>>(
  (ref) => NoteLoader().load(),
);

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

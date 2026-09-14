import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/note_collection.dart';
import '../../domain/models/usage_note.dart';
import '../../shared/widgets/ambient_background.dart';
import 'notes_controller.dart';

/// 筆記。上面切換看哪一本：用法地雷或近義字。
///
/// 版面刻意留白多、線細、沒有厚重的卡片，
/// 因為這頁是拿來讀的，不是拿來操作的。
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(noteCollectionProvider);
    final async = ref.watch(notesProvider(collection));

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const Text('筆記', style: AppText.title),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                const _Switcher(),
                const SizedBox(height: Gap.xs),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: Gap.md),
                  child: Text(collection.subtitle, style: AppText.note),
                ),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到筆記：$e', style: AppText.bodyDim)),
                    data: (notes) => notes.isEmpty
                        ? const Center(
                            child: Text('這本還沒有內容', style: AppText.bodyDim),
                          )
                        : ListView.separated(
                            itemCount: notes.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppColors.glassEdge,
                            ),
                            itemBuilder: (_, i) => _NoteRow(
                              note: notes[i],
                              collection: collection,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 兩本之間切換。做成兩顆並排的標籤，一眼看得出有幾本、現在在哪本。
class _Switcher extends ConsumerWidget {
  const _Switcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(noteCollectionProvider);

    return Row(
      children: [
        for (final c in NoteCollection.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => ref.read(noteCollectionProvider.notifier).state = c,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: c == current
                      ? AppColors.accentSolid
                      : AppColors.glassFill,
                  borderRadius: BorderRadius.circular(Radii.chip),
                  border: Border.all(
                    color: c == current
                        ? Colors.transparent
                        : AppColors.glassEdge,
                  ),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c == current ? Colors.white : AppColors.ink2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.collection});

  final UsageNote note;
  final NoteCollection collection;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/notes/${collection.name}/${note.no}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  note.no,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: AppColors.ink3,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                if (note.status.isNotEmpty)
                  Text(note.status, style: AppText.note),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              note.title,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: AppColors.ink,
              ),
            ),
            if (note.preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                note.preview.replaceAll('**', ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.ink2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

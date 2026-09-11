import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/usage_note.dart';
import '../../shared/widgets/ambient_background.dart';
import 'notes_controller.dart';

/// 用法地雷清單。
///
/// 版面刻意留白多、線細、沒有厚重的卡片，
/// 因為這頁是拿來讀的，不是拿來操作的。
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(usageNotesProvider);

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
                    const Text('用法地雷', style: AppText.title),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: Gap.md),
                  child: Text('字典查得到意思，查不到會不會失禮', style: AppText.note),
                ),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到筆記：$e', style: AppText.bodyDim)),
                    data: (notes) => ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.glassEdge),
                      itemBuilder: (_, i) => _NoteRow(note: notes[i]),
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

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});

  final UsageNote note;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/notes/${note.no}'),
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

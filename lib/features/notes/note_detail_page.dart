import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/usage_note.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/inline_text.dart';
import 'notes_controller.dart';

/// 一則用法地雷的內容。
///
/// 排版的重點是好讀：行距放寬、段落之間留白、小標用細線帶出來。
/// 對照表不畫成格子，改成一列一張卡，手機上才不會擠成一團。
class NoteDetailPage extends ConsumerWidget {
  const NoteDetailPage({super.key, required this.no});

  final String no;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(usageNoteProvider(no));

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 20),
                    color: AppColors.ink2,
                  ),
                ),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到這則：$e', style: AppText.bodyDim)),
                    data: (note) => note == null
                        ? const Center(
                            child: Text('找不到這則', style: AppText.bodyDim),
                          )
                        : _Body(note: note),
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

class _Body extends StatelessWidget {
  const _Body({required this.note});

  final UsageNote note;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          [
            note.no,
            if (note.date.isNotEmpty) note.date,
            note.status,
          ].where((s) => s.isNotEmpty).join('　·　'),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: AppColors.ink3,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          note.title,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            height: 1.3,
            letterSpacing: -0.4,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Gap.lg),

        for (final block in note.blocks) _Block(block: block),

        if (note.relatedWords.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          const _Rule(),
          const SizedBox(height: Gap.md),
          const Text('相關單字', style: AppText.label),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final w in note.relatedWords) _WordChip(word: w)],
          ),
        ],
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});

  final NoteBlock block;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      NoteHeading(:final text) => Padding(
        padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 24, height: 2, color: AppColors.accent),
            const SizedBox(height: Gap.sm),
            Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
      NoteParagraph(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: InlineText(
          text,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.85,
            color: AppColors.ink2,
          ),
        ),
      ),
      NoteQuote(:final text) => Container(
        margin: const EdgeInsets.only(bottom: Gap.md),
        padding: const EdgeInsets.fromLTRB(13, 2, 0, 2),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.ink3, width: 2)),
        ),
        child: InlineText(
          text,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.7,
            color: AppColors.ink3,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      NoteBullets(:final items) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final item in items) _Bullet(text: item)],
        ),
      ),
      NoteTable(:final headers, :final rows) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Column(
          children: [
            for (final row in rows) _TableRow(headers: headers, cells: row),
          ],
        ),
      ),
    };
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 9, right: 10),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: InlineText(
              text,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.7,
                color: AppColors.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 對照表的一列。
///
/// 第一欄當標題，其餘欄位變成「表頭：內容」的說明行。
/// 這樣在窄畫面上也讀得完整，不會被切掉。
class _TableRow extends StatelessWidget {
  const _TableRow({required this.headers, required this.cells});

  final List<String> headers;
  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(Radii.card),
        border: const Border(
          left: BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InlineText(
            cells.first,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          for (var i = 1; i < cells.length; i++) ...[
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    i < headers.length ? headers[i] : '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.ink3,
                      height: 1.6,
                    ),
                  ),
                ),
                Expanded(
                  child: InlineText(
                    cells[i],
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 相關單字。點下去直接跳到那個字的詳情，省得自己再去搜。
class _WordChip extends StatelessWidget {
  const _WordChip({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/word/${Uri.encodeComponent(word)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: Text(
          word,
          style: const TextStyle(fontSize: 12.5, color: AppColors.accent),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.glassEdge);
}

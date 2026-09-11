import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/word.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/status_pill.dart';
import 'library_controller.dart';

/// 單字庫。搜尋、篩狀態、點進去看某個字的詳情。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const Text('單字庫', style: AppText.title),
                  ],
                ),
                const _SearchField(),
                const SizedBox(height: Gap.sm),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到單字：$e', style: AppText.bodyDim)),
                    data: (data) => _List(data: data),
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

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextField(
      autocorrect: false,
      style: const TextStyle(fontSize: 14, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: '搜尋單字或中文',
        hintStyle: const TextStyle(color: AppColors.ink3, fontSize: 14),
        prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.ink3),
        isDense: true,
        filled: true,
        fillColor: AppColors.glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: const BorderSide(color: AppColors.glassEdge),
        ),
      ),
      onChanged: (value) =>
          ref.read(libraryQueryProvider.notifier).state = value,
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.data});

  final LibraryData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(libraryFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Chip(label: '全部', value: null, active: active == null),
              for (final status in WordStatus.values)
                _Chip(
                  label: '${status.label} ${data.counts[status] ?? 0}',
                  value: status,
                  active: active == status,
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: data.words.isEmpty
              ? const Center(child: Text('沒有符合的字', style: AppText.bodyDim))
              : ListView.separated(
                  itemCount: data.words.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.glassEdge),
                  itemBuilder: (context, i) =>
                      _Row(word: data.words[i], confirmRight: data.confirmRight),
                ),
        ),
      ],
    );
  }
}

class _Chip extends ConsumerWidget {
  const _Chip({required this.label, required this.value, required this.active});

  final String label;
  final WordStatus? value;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => ref.read(libraryFilterProvider.notifier).state = value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.accentSolid : AppColors.glassFill,
            borderRadius: BorderRadius.circular(Radii.chip),
            border: Border.all(
              color: active ? Colors.transparent : AppColors.glassEdge,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: active ? Colors.white : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.word, required this.confirmRight});

  final Word word;
  final int confirmRight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/word/${Uri.encodeComponent(word.word)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    word.word,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    word.zh,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.note,
                  ),
                ],
              ),
            ),
            StatusPill(status: word.statusWith(confirmRight)),
            const SizedBox(width: Gap.sm),
            SizedBox(
              width: 46,
              child: Text(
                '${word.right} · ${word.wrong}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.ink2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

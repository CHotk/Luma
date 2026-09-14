import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/word.dart';
import '../../domain/rules_config.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/status_pill.dart';
import '../../shared/widgets/topic_tag.dart';
import '../../shared/widgets/trap_tag.dart';
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
    final total = data.counts.values.fold(0, (sum, n) => sum + n);
    final shown = data.words.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: Gap.sm),
          child: Text(
            // 有篩選或搜尋時兩個數字都要看得到，
            // 只顯示一個會讓人以為單字庫變少了。
            shown == total ? '共 $total 個字' : '顯示 $shown 個，共 $total 個字',
            style: AppText.note,
          ),
        ),
        // 狀態在左邊可以橫向滑，類別固定在右邊不會被滑走。
        // 放這裡而不是塞進搜尋框：搜尋框留給打字，篩選集中在同一列比較好找。
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Chip(
                      label: '全部 $total',
                      value: null,
                      active: active == null,
                    ),
                    for (final status in WordStatus.values)
                      _Chip(
                        label: '${status.label} ${data.counts[status] ?? 0}',
                        value: status,
                        active: active == status,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Gap.xs),
            _TopicMenu(counts: data.topicCounts),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: data.words.isEmpty
              ? const Center(child: Text('沒有符合的字', style: AppText.bodyDim))
              : ListView.separated(
                  itemCount: data.words.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.glassEdge),
                  itemBuilder: (context, i) => _Row(
                    word: data.words[i],
                    rules: data.rules,
                    trapNote: data.traps[data.words[i].word.toLowerCase()],
                  ),
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

/// 類別下拉。跟狀態篩選是「且」的關係，兩個可以同時生效。
class _TopicMenu extends ConsumerWidget {
  const _TopicMenu({required this.counts});

  final Map<WordTopic, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryTopicProvider);
    final tagged = WordTopic.values.where((t) => t.isTagged).toList();

    return PopupMenuButton<WordTopic?>(
      tooltip: '類別',
      color: const Color(0xFF1A1A24),
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          ref.read(libraryTopicProvider.notifier).state = value,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('全部類別')),
        for (final topic in tagged)
          PopupMenuItem(
            value: topic,
            child: Text('${topic.label} ${counts[topic] ?? 0}'),
          ),
        PopupMenuItem(
          value: WordTopic.none,
          child: Text('未分類 ${counts[WordTopic.none] ?? 0}'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
        decoration: BoxDecoration(
          color: selected == null ? AppColors.glassFill : AppColors.accentSolid,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(
            color: selected == null ? AppColors.glassEdge : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected?.label ?? '類別',
              style: TextStyle(
                fontSize: 11.5,
                color: selected == null ? AppColors.ink2 : Colors.white,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: selected == null ? AppColors.ink3 : Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.word, required this.rules, this.trapNote});

  final Word word;
  final RulesConfig rules;

  /// 這個字是地雷字的話，對應到第幾則筆記。不是就是 null。
  final String? trapNote;

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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          word.zh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.note,
                        ),
                      ),
                      if (trapNote != null) ...[
                        const SizedBox(width: 6),
                        TrapTag(noteNo: trapNote!),
                      ],
                      if (word.topic.isTagged) ...[
                        const SizedBox(width: 6),
                        TopicTag(topic: word.topic),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            StatusPill(status: word.statusWith(rules)),
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

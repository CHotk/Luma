import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/seed/app_defaults_loader.dart';
import '../../domain/models/word.dart';
import '../../domain/rules_config.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/sense_tag.dart';
import '../../shared/widgets/status_pill.dart';
import '../../shared/widgets/tag_badge.dart';
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
                    const Spacer(),
                    // 掌握的字另外有一頁攤開例句，入口放這裡最好找。
                    IconButton(
                      onPressed: () => context.push('/mastered'),
                      icon: const Icon(
                        Icons.workspace_premium_outlined,
                        size: 20,
                      ),
                      color: AppColors.statusMastered,
                      tooltip: '已經掌握',
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(child: _SearchField()),
                    const SizedBox(width: Gap.xs),
                    const _SortButton(),
                  ],
                ),
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
        hintText: '搜尋單字、中文或標籤',
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

/// 排序方式。只決定「同一種狀態裡面」怎麼排，不會打亂狀態分組。
class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySortProvider);

    return PopupMenuButton<LibrarySort>(
      tooltip: '排序方式',
      color: const Color(0xFF1A1A24),
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          ref.read(librarySortProvider.notifier).state = value,
      itemBuilder: (context) => [
        for (final mode in LibrarySort.values)
          PopupMenuItem(
            value: mode,
            child: Row(
              children: [
                Icon(
                  mode == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: mode == selected ? AppColors.accent : AppColors.ink3,
                ),
                const SizedBox(width: Gap.sm),
                Text(mode.label),
              ],
            ),
          ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(Radii.button),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: const Icon(
          Icons.sort_rounded,
          size: 18,
          color: AppColors.ink2,
        ),
      ),
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
        // 狀態在左邊可以橫向滑，標籤固定在右邊不會被滑走。
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
            _TagMenu(counts: data.tagCounts, multiTagCount: data.multiTagCount),
            const SizedBox(width: Gap.xs),
            _SenseMenu(counts: data.senseCounts),
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

/// 標籤篩選按鈕。跟狀態篩選是「且」的關係，兩個可以同時生效。
///
/// 2026-09-16 之前這裡篩的是固定選項的「類別」（`WordTopic`），使用者決定
/// 拿掉那個分類軸，選單改成直接列出資料裡實際出現過的所有標籤
/// （`data.tagCounts` 的鍵），不是列舉某個 enum——新增一種標籤完全不用
/// 改這裡的程式，題庫檔多打一個字就會自動出現在選單裡。
///
/// **可以多選**（使用者 2026-09-16 決定）：`PopupMenuButton` 選一項就會
/// 自動關掉選單，沒辦法勾好幾項，所以改用 `showDialog` 彈出一個置中的
/// 對話框，勾選會即時套用篩選，對話框本身留著，直到使用者按「完成」或
/// 點外面才關。一開始做成從底部彈出的 bottom sheet，使用者覺得醜
/// （2026-09-16 決定改成置中對話框，跟這頁其他對話框一致）。
/// [multiTagLabel]（自己貼了兩個以上標籤的字）固定排在選單最下面，
/// 用分隔線跟一般標籤隔開，因為它篩的是「標籤數量」而不是某個標籤本身，
/// 混在字母排序裡容易被誤會成一個普通標籤。
/// 標籤清單的顯示順序：先字母序，再套使用者在
/// `assets/config/app_defaults.yaml`（`libraryTagAdjacentGroups`／
/// `libraryTagTrailingOrder`）指定的偏好（使用者 2026-09-17 決定）。
/// 標籤清單裡沒有的偏好項目就跳過，不強求。
List<String> sortLibraryTags(Iterable<String> raw, LibraryTagOrder order) {
  final tags = raw.toList()..sort();

  for (final group in order.adjacentGroups) {
    for (var i = 1; i < group.length; i++) {
      final anchor = group[i - 1];
      final tag = group[i];
      if (!tags.contains(anchor) || !tags.contains(tag)) continue;
      tags.remove(tag);
      tags.insert(tags.indexOf(anchor) + 1, tag);
    }
  }

  for (final tag in order.trailingOrder) {
    if (tags.remove(tag)) tags.add(tag);
  }

  return tags;
}

class _TagMenu extends ConsumerWidget {
  const _TagMenu({required this.counts, required this.multiTagCount});

  final Map<String, int> counts;
  final int multiTagCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryTagProvider);
    final order = ref.watch(libraryTagOrderProvider);
    final tags = sortLibraryTags(
      counts.keys.where((t) => t != untaggedLabel),
      order,
    );

    String label() {
      if (selected.isEmpty) return '標籤';
      if (selected.length == 1) return selected.first;
      return '標籤（${selected.length}）';
    }

    return GestureDetector(
      onTap: () => _openDialog(context, ref, tags),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
        decoration: BoxDecoration(
          color: selected.isEmpty
              ? AppColors.glassFill
              : AppColors.accentSolid,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(
            color: selected.isEmpty
                ? AppColors.glassEdge
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label(),
              style: TextStyle(
                fontSize: 11.5,
                color: selected.isEmpty ? AppColors.ink2 : Colors.white,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: selected.isEmpty ? AppColors.ink3 : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  /// 第一版是平的 `AlertDialog`、單一背景色，使用者嫌單調
  /// （2026-09-16 決定）：改成跟 [GlassCard] 同一套毛玻璃處理（模糊、
  /// 半透明、亮邊），每個標籤也從純文字+checkbox 改成跟頁面上方狀態篩選
  /// 同款的膠囊型 chip（選到用主色實心填滿），整個對話框的視覺語言才會
  /// 跟這頁其他篩選 UI 一致，不是自己另外發明一套。
  void _openDialog(BuildContext context, WidgetRef ref, List<String> tags) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final selected = ref.watch(libraryTagProvider);

          void toggle(String value) {
            final next = {...selected};
            if (!next.remove(value)) next.add(value);
            ref.read(libraryTagProvider.notifier).state = next;
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.card),
                    border: Border.all(color: AppColors.glassEdge),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC22222E), Color(0xE615151D)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Gap.lg,
                          Gap.lg,
                          Gap.lg,
                          Gap.sm,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '標籤（可複選）',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const Spacer(),
                            if (selected.isNotEmpty)
                              GestureDetector(
                                onTap: () =>
                                    ref
                                            .read(libraryTagProvider.notifier)
                                            .state =
                                        const {},
                                child: const Text(
                                  '清除',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.lg,
                          ),
                          child: Column(
                            children: [
                              if (counts.containsKey(untaggedLabel))
                                _TagChip(
                                  label: untaggedLabel,
                                  count: counts[untaggedLabel] ?? 0,
                                  selected: selected.contains(untaggedLabel),
                                  onTap: () => toggle(untaggedLabel),
                                ),
                              for (final tag in tags)
                                _TagChip(
                                  label: tag,
                                  count: counts[tag] ?? 0,
                                  selected: selected.contains(tag),
                                  onTap: () => toggle(tag),
                                ),
                              _TagChip(
                                label: multiTagLabel,
                                count: multiTagCount,
                                selected: selected.contains(multiTagLabel),
                                onTap: () => toggle(multiTagLabel),
                                accentBorder: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(Gap.lg),
                        child: GlassButton(
                          label: '完成',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 標籤選擇用的整排列，一行一個標籤，靠左標籤名、靠右數字，選到整排
/// 用主色填滿。原本用 [Wrap] 排成一團膠囊 chip，長短不一排起來很亂
/// （使用者 2026-09-16 嫌醜），改成單欄縱向排列，對齊乾淨很多。
/// [accentBorder]：[multiTagLabel] 篩的是「標籤數量」不是某個標籤本身，
/// 未選取時用主色細框跟一般標籤區分開，不用額外文字說明。
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.accentBorder = false,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool accentBorder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSolid : AppColors.glassFill,
            borderRadius: BorderRadius.circular(Radii.button),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : accentBorder
                  ? AppColors.accent
                  : AppColors.glassEdge,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 15,
                color: selected ? Colors.white : AppColors.ink3,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white70 : AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 詞義豐富度下拉。跟狀態、標籤都是「且」的關係，可以同時生效。
class _SenseMenu extends ConsumerWidget {
  const _SenseMenu({required this.counts});

  final Map<WordSenseCount, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySenseProvider);
    final tagged = WordSenseCount.values.where((s) => s.isTagged).toList();

    return PopupMenuButton<WordSenseCount?>(
      tooltip: '詞義豐富度',
      color: const Color(0xFF1A1A24),
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          ref.read(librarySenseProvider.notifier).state = value,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('全部詞義')),
        for (final sense in tagged)
          PopupMenuItem(
            value: sense,
            child: Text('${sense.label} ${counts[sense] ?? 0}'),
          ),
        PopupMenuItem(
          value: WordSenseCount.none,
          child: Text('未分類 ${counts[WordSenseCount.none] ?? 0}'),
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
              selected?.label ?? '詞義',
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
                      if (word.tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        TagBadge(tags: word.tags),
                      ],
                      if (word.senseCount.isTagged) ...[
                        const SizedBox(width: 6),
                        SenseTag(senseCount: word.senseCount),
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

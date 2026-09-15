import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/word.dart';
import '../../domain/rules_config.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/sense_tag.dart';
import '../../shared/widgets/topic_tag.dart';
import '../../shared/widgets/trap_tag.dart';
import '../notes/notes_controller.dart';

/// 已經掌握的字，以及怎麼用它們。
///
/// 跟單字庫的「掌握」篩選不同：那裡是一列一行的清單，
/// 這裡一個字一張卡，例句直接攤開，重點是看得到用法而不是數數量。
class MasteredPage extends ConsumerWidget {
  const MasteredPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(masteredProvider);

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
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.ink2,
                    ),
                    const Text('已經掌握', style: AppText.title),
                  ],
                ),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('讀不到資料：$e', style: AppText.bodyDim)),
                    data: (data) => _Body(data: data),
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

/// 這頁要的資料。
typedef MasteredData = ({
  List<Word> words,
  int total,
  Map<String, String> traps,
  RulesConfig rules,
});

final masteredProvider = FutureProvider.autoDispose<MasteredData>((ref) async {
  ref.watch(dataRevisionProvider);
  final all = await ref.watch(wordRepositoryProvider).loadAll();
  final rules = await ref.watch(settingsRepositoryProvider).loadRules();
  final traps = await ref.watch(trapWordsProvider.future);

  final mastered =
      all.where((w) => w.statusWith(rules) == WordStatus.confirmed).toList()
        // 最近考過的排前面，剛掌握的那個會在最上面，比較有成就感。
        ..sort((a, b) {
          final at = a.lastTest;
          final bt = b.lastTest;
          if (at == null && bt == null) return a.id.compareTo(b.id);
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

  return (words: mastered, total: all.length, traps: traps, rules: rules);
});

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final MasteredData data;

  @override
  Widget build(BuildContext context) {
    if (data.words.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Gap.xl),
          child: Text(
            '還沒有掌握的字。\n沒錯過的字答對三次、錯過的字答對七倍，就會出現在這裡。',
            textAlign: TextAlign.center,
            style: AppText.bodyDim,
          ),
        ),
      );
    }

    final percent = data.total == 0
        ? 0
        : (data.words.length / data.total * 100).round();

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: Gap.md),
          child: Text(
            '${data.words.length} 個字，佔單字庫的 $percent%',
            style: AppText.note,
          ),
        ),
        for (final word in data.words)
          _Card(word: word, trapNote: data.traps[word.word.toLowerCase()]),
        const SizedBox(height: Gap.lg),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Gap.md),
          child: Text(
            '掌握之後對錯次數還是繼續累計，每輪也會固定回頭考一個，'
            '所以這裡的字不是從此不再出現。',
            textAlign: TextAlign.center,
            style: AppText.note,
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// 一個字一張卡。重點是例句，那是「怎麼用」最直接的答案。
class _Card extends StatelessWidget {
  const _Card({required this.word, this.trapNote});

  final Word word;
  final String? trapNote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: GlassCard(
        onTap: () => context.push('/word/${Uri.encodeComponent(word.word)}'),
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  word.word,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Text(
                    '${word.pos}　${word.zh}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyDim,
                  ),
                ),
              ],
            ),

            const SizedBox(height: Gap.sm),
            if (word.example.isNotEmpty)
              Text(
                word.example,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.6,
                  color: AppColors.ink,
                ),
              )
            else
              const Text('還沒有例句。之後補上例句，這裡就會顯示怎麼用。', style: AppText.note),

            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Text(
                  '答對 ${word.right} 次'
                  '${word.wrong > 0 ? '，曾錯 ${word.wrong} 次' : '，沒錯過'}',
                  style: AppText.note,
                ),
                const Spacer(),
                if (trapNote != null) ...[
                  TrapTag(noteNo: trapNote!, tappable: true),
                  const SizedBox(width: 6),
                ],
                TopicTag(topics: word.topics),
                if (word.senseCount.isTagged) ...[
                  const SizedBox(width: 6),
                  SenseTag(senseCount: word.senseCount),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

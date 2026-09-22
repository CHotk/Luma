import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../domain/models/history.dart';
import '../../domain/models/word.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/sense_tag.dart';
import '../../shared/widgets/speaker_button.dart';
import '../../shared/widgets/status_pill.dart';
import '../../shared/widgets/tag_badge.dart';
import '../../shared/widgets/trap_tag.dart';
import 'word_detail_controller.dart';

/// 單字詳情。目前有基本資料、作答歷史跟發音，
/// 音標、自然拼讀拆解、配圖排在之後做。
class WordDetailPage extends ConsumerWidget {
  const WordDetailPage({super.key, required this.word});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wordDetailProvider(word));

    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.sm),
                AppTopBar(title: word),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, _) =>
                        Center(child: Text('$e', style: AppText.bodyDim)),
                    data: (detail) => _Body(detail: detail),
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
  const _Body({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context) {
    final word = detail.word;

    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          word.word,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      SpeakerButton(text: word.word, size: 22),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${word.pos}　${word.zh}',
                          style: AppText.bodyDim,
                        ),
                      ),
                      if (detail.trapNote != null) ...[
                        const SizedBox(width: Gap.sm),
                        TrapTag(noteNo: detail.trapNote!, tappable: true),
                      ],
                      if (word.tags.isNotEmpty) ...[
                        const SizedBox(width: Gap.sm),
                        TagBadge(tags: word.tags),
                      ],
                      if (word.senseCount.isTagged) ...[
                        const SizedBox(width: Gap.sm),
                        SenseTag(
                          senseCount: word.senseCount,
                          noteNo: detail.senseNote,
                          tappable: true,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            StatusPill(status: word.statusWith(detail.rules)),
          ],
        ),
        const SizedBox(height: Gap.md),

        if (word.example.isNotEmpty) ...[
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelLabel('例句'),
                const SizedBox(height: Gap.xs),
                Text(word.example, style: AppText.body),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],

        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelLabel('累計'),
              const SizedBox(height: Gap.sm),
              _Row('答對', '${word.right} 次'),
              _Row('答錯', '${word.wrong} 次'),
              _Row('階段', word.grade.label),
              if (word.statusWith(detail.rules) == WordStatus.confirmed)
                _Row('狀態', '已經掌握，次數繼續累計')
              else
                _Row('離掌握還差', '${word.rightNeededFor(detail.rules)} 次答對'),
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),
        const PanelLabel('作答歷史'),
        const SizedBox(height: Gap.xs),
        if (detail.history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Gap.lg),
            child: Text('這個字還沒被考過', style: AppText.bodyDim),
          )
        else
          for (final entry in detail.history) _HistoryRow(entry: entry),

        const SizedBox(height: Gap.lg),
        const Text(
          '音標、自然拼讀拆解與配圖排在之後做',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// 一次作答。年月日時分都列出來，答對答錯用顏色分。
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    // 從 history.txt 匯進來的舊紀錄沒有時分也沒有秒數，
    // 這裡就不要假裝有，直接只顯示日期。
    final hasClock = entry.at.hour != 0 || entry.at.minute != 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.glassEdge)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              entry.correct ? 'O' : 'X',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: entry.correct ? AppColors.ok : AppColors.bad,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasClock ? _stamp(entry.at) : _day(entry.at),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.ink,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                // 打字題才有打了什麼，點選題只有會/不會，沒有輸入內容可看。
                // 特別是答錯的時候，光知道錯了沒有用，要看到當初打的內容
                // 才翻得出是哪個字母拼錯（見 HistoryEntry.input 的註解）。
                if (entry.typed && entry.input.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '打了：${entry.input}',
                      style: TextStyle(
                        fontSize: 12,
                        color: entry.correct
                            ? AppColors.ink3
                            : AppColors.bad,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            entry.seconds > 0 ? '想了 ${entry.seconds} 秒' : '沒有計時',
            style: AppText.note,
          ),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _stamp(DateTime d) =>
      '${_day(d)} ${_two(d.hour)}:${_two(d.minute)}';
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.bodyDim),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

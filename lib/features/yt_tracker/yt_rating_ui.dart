import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_rating_store.dart';
import '../../data/services/youtube_api_service.dart';

/// 幣圈影片準度評價的畫面元件（2026-11-11，設計稿「最終版」）。
/// 分類名有「幣圈」才會出現，資料記在影片上，換分類照樣留著。

/// 分類名是不是幣圈。
bool isCryptoCategoryName(String name) => name.contains('幣圈');

/// 影片篩選「待驗證／對／半對／不對／沒給方向」：[key] 是 pending 或 [YtVerdict.name]。
bool ytRatingMatches(YtVideoRating? r, String key) {
  if (r == null) return false;
  if (key == 'pending') return r.pending;
  return r.verdict?.name == key;
}

Color ytVerdictColor(YtVerdict v) => switch (v) {
  YtVerdict.ok => AppColors.ok,
  YtVerdict.half => AppColors.mid,
  YtVerdict.bad => AppColors.bad,
  YtVerdict.none => AppColors.ink3,
};

IconData ytVerdictIcon(YtVerdict v) => switch (v) {
  YtVerdict.ok => Icons.panorama_fish_eye_rounded, // ○
  YtVerdict.half => Icons.change_history_rounded, // △
  YtVerdict.bad => Icons.close_rounded, // ✕
  YtVerdict.none => Icons.remove_rounded, // —
};

/// 頻道準度的顏色（命中率高低）。
Color ytAccuracyColor(YtAccuracy a) {
  final g = a.grade;
  return switch (g) {
    'S' || 'A' => AppColors.ok,
    'B' => AppColors.mid,
    'C' => AppColors.bad,
    _ => AppColors.ink3,
  };
}

/// 改評價的動作（記到本機、更新畫面）。
class YtRatingActions {
  YtRatingActions(this.ref);
  final WidgetRef ref;

  Map<String, YtVideoRating> get _all => ref.read(ytVideoRatingsProvider);

  Future<void> _save(String videoId, YtVideoRating r) async {
    final next = {..._all};
    r.isEmpty ? next.remove(videoId) : next[videoId] = r;
    ref.read(ytVideoRatingsProvider.notifier).state = next;
    await YtVideoRatingStore(ref.read(keyValueStoreProvider)).set(videoId, r);
  }

  YtVideoRating _base(YoutubeVideo v, String channelId, String channelName) {
    final old = _all[v.videoId];
    return (old ?? YtVideoRating(at: DateTime.now())).copyWith(
      at: DateTime.now(),
      channelId: channelId.isNotEmpty ? channelId : null,
      channelName: channelName.isNotEmpty ? channelName : null,
      title: v.title,
    );
  }

  /// 評價；已經是這個評價再按一次就取消（變回待驗證或沒評）。
  Future<void> rate(
    YoutubeVideo v,
    String channelId,
    String channelName,
    YtVerdict verdict, {
    String? note,
    bool toggle = true,
  }) async {
    final old = _all[v.videoId];
    final base = _base(v, channelId, channelName);
    if (toggle && old?.verdict == verdict) {
      await _save(
        v.videoId,
        base.copyWith(clearVerdict: true, clearRatedAt: true),
      );
      return;
    }
    await _save(
      v.videoId,
      base.copyWith(verdict: verdict, ratedAt: DateTime.now(), note: note),
    );
  }

  /// 記預測：影片說了什麼、幾天後驗證。會把原本的評價清掉（重新驗證）。
  Future<void> predict(
    YoutubeVideo v,
    String channelId,
    String channelName,
    String claim,
    int days,
  ) async {
    final base = _base(v, channelId, channelName);
    final d = DateTime.now().add(Duration(days: days));
    await _save(
      v.videoId,
      base.copyWith(
        claim: claim.trim(),
        dueAt: DateTime(d.year, d.month, d.day),
        clearVerdict: true,
        clearRatedAt: true,
      ),
    );
  }

  /// 全部清掉（評價、預測、備註）。
  Future<void> clear(YoutubeVideo v) async {
    final old = _all[v.videoId];
    if (old == null) return;
    await _save(
      v.videoId,
      YtVideoRating(
        at: DateTime.now(),
        channelId: old.channelId,
        channelName: old.channelName,
        title: old.title,
      ),
    );
  }
}

/// 縮圖左下角的評價小標籤（位置跟「♪ 歌曲」一樣）。沒評也沒預測不顯示。
class YtRatingPill extends StatelessWidget {
  const YtRatingPill({super.key, required this.rating});
  final YtVideoRating rating;

  @override
  Widget build(BuildContext context) {
    final v = rating.verdict;
    final String text;
    final Color color;
    if (v != null) {
      text = '${v.mark} ${v.label}';
      color = ytVerdictColor(v);
    } else if (rating.pending) {
      final due = rating.isDue(DateTime.now());
      text = due ? '🔔 該驗證' : '⏳ ${_daysLeft(rating)} 天後驗證';
      color = due ? const Color(0xFFFF9F0A) : const Color(0xFF0A84FF);
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: v == YtVerdict.none ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}

int _daysLeft(YtVideoRating r) {
  final due = r.dueAt!;
  final today = DateTime.now();
  return DateTime(
    due.year,
    due.month,
    due.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
}

/// 影片列下面的「預測」說明＋直接驗證的四顆鈕（待驗證才有）。
class YtVerifyStrip extends StatelessWidget {
  const YtVerifyStrip({
    super.key,
    required this.rating,
    required this.onVerdict,
  });
  final YtVideoRating rating;
  final ValueChanged<YtVerdict> onVerdict;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rating.claim.isNotEmpty)
            // 完整顯示，不截斷（2026-11-13 使用者要求）。
            Text(
              '預測：${rating.claim}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.ink2),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final v in YtVerdict.values)
                InkWell(
                  onTap: () => onVerdict(v),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: ytVerdictColor(v).withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      switch (v) {
                        YtVerdict.ok => '○ 說對',
                        YtVerdict.half => '△ 半對',
                        YtVerdict.bad => '✕ 說錯',
                        YtVerdict.none => '— 沒方向',
                      },
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ytVerdictColor(v),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 居中的評價視窗（使用者要求不要底部視窗）：四種評價＋備註＋預測＋清除。
Future<void> showYtRatingDialog(
  BuildContext context,
  WidgetRef ref, {
  required YoutubeVideo video,
  required String channelId,
  required String channelName,
}) async {
  final actions = YtRatingActions(ref);
  final old = ref.read(ytVideoRatingsProvider)[video.videoId];
  final noteCtrl = TextEditingController(text: old?.note ?? '');
  final choice = await showDialog<Object>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      title: const Text(
        '這部影片說得準嗎？',
        style: TextStyle(color: AppColors.ink, fontSize: 16),
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.note,
              ),
              if (old != null && old.claim.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '預測：${old.claim}',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in YtVerdict.values)
                    _VerdictButton(
                      verdict: v,
                      selected: old?.verdict == v,
                      onTap: () => Navigator.pop(ctx, v),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text('「沒給方向」＝影片沒講漲跌，不算進命中率', style: AppText.note),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '備註（選填）',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (old != null && !old.isEmpty)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'clear'),
            child: const Text('清除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'predict'),
          child: const Text('記預測'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('關閉'),
        ),
      ],
    ),
  );
  final note = noteCtrl.text.trim();
  // 不在這裡 dispose：視窗關掉的動畫還在用這個輸入框（2026-11-11 測試抓到），交給 GC。
  if (!context.mounted) return;
  if (choice is YtVerdict) {
    await actions.rate(
      video,
      channelId,
      channelName,
      choice,
      note: note,
      toggle: false,
    );
  } else if (choice == 'clear') {
    await actions.clear(video);
  } else if (choice == 'predict') {
    await showYtPredictDialog(
      context,
      ref,
      video: video,
      channelId: channelId,
      channelName: channelName,
    );
  }
}

class _VerdictButton extends StatelessWidget {
  const _VerdictButton({
    required this.verdict,
    required this.selected,
    required this.onTap,
  });
  final YtVerdict verdict;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ytVerdictColor(verdict);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        key: ValueKey('verdict_${verdict.name}'),
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: selected ? 1 : 0.5)),
        ),
        child: Column(
          children: [
            Icon(ytVerdictIcon(verdict), color: c, size: 24),
            const SizedBox(height: 4),
            Text(
              verdict.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 記預測：影片說了什麼、幾天後驗證。
Future<void> showYtPredictDialog(
  BuildContext context,
  WidgetRef ref, {
  required YoutubeVideo video,
  required String channelId,
  required String channelName,
}) async {
  final old = ref.read(ytVideoRatingsProvider)[video.videoId];
  final ctrl = TextEditingController(text: old?.claim ?? '');
  var days = 14;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text(
          '記下他的預測',
          style: TextStyle(color: AppColors.ink, fontSize: 16),
        ),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.note,
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('predict_claim'),
                  controller: ctrl,
                  autofocus: true,
                  // 跟著字數長高，最多一次顯示五行，再多就在框裡捲（2026-11-13 使用者要求）。
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '他說了什麼？例如 BTC 兩週內站上 8 萬',
                  ),
                ),
                const SizedBox(height: 12),
                Text('幾天後驗證', style: AppText.note),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in const [3, 7, 14, 30, 90])
                      ChoiceChip(
                        key: ValueKey('predict_days_$d'),
                        label: Text('$d 天'),
                        selected: days == d,
                        onSelected: (_) => setS(() => days = d),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('predict_ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('記下來'),
          ),
        ],
      ),
    ),
  );
  final claim = ctrl.text;
  // 不在這裡 dispose：視窗關掉的動畫還在用這個輸入框（2026-11-11 測試抓到），交給 GC。
  if (ok != true) return;
  await YtRatingActions(
    ref,
  ).predict(video, channelId, channelName, claim, days);
}

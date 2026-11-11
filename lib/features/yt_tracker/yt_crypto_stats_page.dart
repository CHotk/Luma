import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_rating_store.dart';
import '../../shared/widgets/ambient_background.dart';
import 'yt_rating_ui.dart';

/// 幣圈「準度統計」（2026-11-11，設計稿最終版的第三部分）：整體命中率、評價分佈、
/// 頻道排行（段位篩選、至少幾部、排序）、最近評價紀錄。[channelId] 有給＝只看那個頻道
/// （頻道頁的「準度」點進來）：該頻道的命中率、依評價篩影片、評價紀錄。
///
/// 只看評價資料本身（記在影片上、帶頻道 id／名稱），不用另外抓 YouTube。
class YtCryptoStatsPage extends ConsumerStatefulWidget {
  const YtCryptoStatsPage({
    super.key,
    this.channelId,
    this.channelName,
    this.channelNames = const {},
  });

  final String? channelId;
  final String? channelName;

  /// 頻道 id → 目前的名稱（評價紀錄裡存的名稱可能是舊的）。
  final Map<String, String> channelNames;

  @override
  ConsumerState<YtCryptoStatsPage> createState() => _YtCryptoStatsPageState();
}

enum _RankSort {
  rate('準度 高→低'),
  count('評價數 多→少'),
  pending('待驗證 多→少');

  const _RankSort(this.label);
  final String label;
}

class _YtCryptoStatsPageState extends ConsumerState<YtCryptoStatsPage> {
  String? _grade; // null＝全部段位
  int _minCount = YtAccuracy.minSample;
  _RankSort _sort = _RankSort.rate;
  YtVerdict? _verdictFilter;
  bool _pendingOnly = false;

  String _nameOf(String id, Iterable<YtVideoRating> rs) =>
      widget.channelNames[id] ??
      rs
          .firstWhere((r) => r.channelName.isNotEmpty, orElse: () => rs.first)
          .channelName;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ytVideoRatingsProvider);
    final scoped = widget.channelId == null
        ? all
        : {
            for (final e in all.entries)
              if (e.value.channelId == widget.channelId) e.key: e.value,
          };
    final total = ytAccuracyOf(scoped.values);
    final single = widget.channelId != null;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.ink2,
                    ),
                    const Icon(
                      Icons.my_location_rounded,
                      color: AppColors.ytAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        single ? '${widget.channelName ?? '頻道'}・準度' : '幣圈準度統計',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.screenSide,
                    8,
                    Gap.screenSide,
                    32,
                  ),
                  children: [
                    _summary(total),
                    const SizedBox(height: Gap.md),
                    if (!single) ..._ranking(scoped),
                    if (single) ..._videos(scoped),
                    const SizedBox(height: Gap.md),
                    ..._log(scoped),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.glassFill,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.glassEdge),
    ),
    child: child,
  );

  Widget _summary(YtAccuracy a) {
    final rate = a.rate;
    Widget stat(String n, String label, Color c) => Expanded(
      child: Column(
        children: [
          Text(
            n,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.note),
        ],
      ),
    );
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (rate ?? 0) / 100,
                        strokeWidth: 7,
                        backgroundColor: Colors.white.withValues(alpha: .08),
                        color: ytAccuracyColor(a),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.enough ? '${rate!.round()}%' : '—',
                          key: const ValueKey('statsRate'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          a.enough ? '命中率' : '資料少',
                          style: AppText.note.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (a.grade != null)
                      Text(
                        '段位 ${a.grade}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ytAccuracyColor(a),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '已評 ${a.rated} 部・待驗證 ${a.pending} 部\n'
                      '命中率＝(○＋△×0.5)÷已評；「沒給方向」不算'
                      '${a.enough ? '' : '；至少 ${YtAccuracy.minSample} 部才給百分比'}',
                      style: AppText.note,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              stat('${a.ok}', '○ 對', AppColors.ok),
              stat('${a.half}', '△ 半對', AppColors.mid),
              stat('${a.bad}', '✕ 不對', AppColors.bad),
              stat('${a.none}', '— 沒方向', AppColors.ink3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Key? key}) =>
      Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );

  List<Widget> _ranking(Map<String, YtVideoRating> all) {
    final byChannel = <String, List<YtVideoRating>>{};
    for (final r in all.values) {
      if (r.channelId.isEmpty) continue;
      byChannel.putIfAbsent(r.channelId, () => []).add(r);
    }
    final rows = [
      for (final e in byChannel.entries)
        (id: e.key, name: _nameOf(e.key, e.value), acc: ytAccuracyOf(e.value)),
    ];
    final shown =
        rows
            .where(
              (r) =>
                  r.acc.rated >= _minCount &&
                  (_grade == null || r.acc.grade == _grade),
            )
            .toList()
          ..sort((a, b) {
            switch (_sort) {
              case _RankSort.rate:
                return (b.acc.rate ?? -1).compareTo(a.acc.rate ?? -1);
              case _RankSort.count:
                return b.acc.rated.compareTo(a.acc.rated);
              case _RankSort.pending:
                return b.acc.pending.compareTo(a.acc.pending);
            }
          });
    final hidden = rows.length - shown.length;
    return [
      Text('頻道排行', style: _h),
      const SizedBox(height: 8),
      Wrap(
        children: [
          _chip('全部段位', _grade == null, () => setState(() => _grade = null)),
          for (final g in const ['S', 'A', 'B', 'C'])
            _chip(
              g,
              _grade == g,
              () => setState(() => _grade = _grade == g ? null : g),
              key: ValueKey('grade_$g'),
            ),
        ],
      ),
      Wrap(
        children: [
          for (final n in const [1, 3, 5, 10])
            _chip(
              '至少 $n 部',
              _minCount == n,
              () => setState(() => _minCount = n),
              key: ValueKey('min_$n'),
            ),
        ],
      ),
      Wrap(
        children: [
          for (final s in _RankSort.values)
            _chip(s.label, _sort == s, () => setState(() => _sort = s)),
        ],
      ),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            rows.isEmpty
                ? '還沒有評價。到幣圈分類的影片往左滑按「對／不對」就會出現在這裡'
                : '沒有符合條件的頻道（評價數不夠的先藏起來了）',
            style: AppText.note,
          ),
        )
      else
        for (final (i, r) in shown.indexed)
          InkWell(
            key: ValueKey('rank_${r.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => YtCryptoStatsPage(
                  channelId: r.id,
                  channelName: r.name,
                  channelNames: widget.channelNames,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      i < 3 ? const ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.name.isEmpty ? '（不知道名稱的頻道）' : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Text(
                    '${r.acc.rated} 部${r.acc.pending > 0 ? '・待 ${r.acc.pending}' : ''}  ',
                    style: AppText.note,
                  ),
                  Text(
                    r.acc.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ytAccuracyColor(r.acc),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ),
          ),
      if (hidden > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('另外 $hidden 個頻道不符合條件，先藏起來', style: AppText.note),
        ),
    ];
  }

  /// 單一頻道：依評價篩影片。
  List<Widget> _videos(Map<String, YtVideoRating> all) {
    final list =
        all.entries
            .where(
              (e) => _pendingOnly
                  ? e.value.pending
                  : (_verdictFilter == null ||
                        e.value.verdict == _verdictFilter),
            )
            .toList()
          ..sort(
            (a, b) => (b.value.ratedAt ?? b.value.at).compareTo(
              a.value.ratedAt ?? a.value.at,
            ),
          );
    return [
      Text('依評價看影片', style: _h),
      const SizedBox(height: 8),
      Wrap(
        children: [
          _chip(
            '全部',
            _verdictFilter == null && !_pendingOnly,
            () => setState(() {
              _verdictFilter = null;
              _pendingOnly = false;
            }),
          ),
          _chip(
            '🎯 待驗證',
            _pendingOnly,
            () => setState(() {
              _pendingOnly = !_pendingOnly;
              _verdictFilter = null;
            }),
          ),
          for (final v in YtVerdict.values)
            _chip(
              '${v.mark} ${v.label}',
              _verdictFilter == v,
              () => setState(() {
                _verdictFilter = _verdictFilter == v ? null : v;
                _pendingOnly = false;
              }),
            ),
        ],
      ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('沒有符合的影片', style: AppText.note),
        )
      else
        for (final e in list) _ratingRow(e.value),
    ];
  }

  Widget _ratingRow(YtVideoRating r) {
    final v = r.verdict;
    final when = r.ratedAt ?? r.at;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: v != null
                ? Icon(ytVerdictIcon(v), size: 18, color: ytVerdictColor(v))
                : const Icon(
                    Icons.hourglass_top_rounded,
                    size: 17,
                    color: Color(0xFF0A84FF),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title.isEmpty ? '（沒有標題）' : r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
                if (r.claim.isNotEmpty)
                  Text(
                    '預測：${r.claim}',
                    style: AppText.note.copyWith(color: AppColors.ink2),
                  ),
                if (r.note.isNotEmpty)
                  Text('備註：${r.note}', style: AppText.note),
                Text(
                  '${widget.channelId == null && r.channelName.isNotEmpty ? '${r.channelName}・' : ''}'
                  '${v?.label ?? (r.pending ? (r.isDue(DateTime.now()) ? '該驗證了' : '待驗證') : '')}・'
                  '${when.year}/${when.month}/${when.day}',
                  style: AppText.note.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 最近評價紀錄（新到舊，最多 30 筆；完整紀錄在資料裡都留著）。
  List<Widget> _log(Map<String, YtVideoRating> all) {
    final list = all.values.where((r) => r.verdict != null).toList()
      ..sort((a, b) => (b.ratedAt ?? b.at).compareTo(a.ratedAt ?? a.at));
    if (list.isEmpty || widget.channelId != null) return const [];
    return [
      Text('最近評價', style: _h),
      const SizedBox(height: 6),
      for (final r in list.take(30)) _ratingRow(r),
      if (list.length > 30)
        Text('還有 ${list.length - 30} 筆沒列出來', style: AppText.note),
    ];
  }
}

const _h = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w800,
  color: AppColors.ink,
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_channel_log_store.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../data/services/youtube_api_service.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';
import 'yt_video_row.dart';

/// 時間軸上的一列。
class YtChannelLogItem {
  const YtChannelLogItem({
    required this.at,
    required this.icon,
    required this.color,
    required this.text,
    this.note,
    required this.isWatch,
    this.channel,
    this.video,
  });

  final DateTime at;
  final IconData icon;
  final Color color;
  final String text;
  final String? note;

  /// 看影片的紀錄（篩選「只看影片」用）。
  final bool isWatch;

  /// 全部頻道的紀錄才會帶：這一列是哪個頻道的（畫面顯示頻道名稱、點一下
  /// 進頻道詳情頁、依分類篩選用）。
  final YtChannel? channel;

  /// 觀看紀錄才有：看的是哪支影片，畫面上整列畫成跟影片清單一樣的影片列
  /// （2026-10-06 使用者要求），左邊照樣是觀看時間。
  final YoutubeVideo? video;

  YtChannelLogItem withChannel(YtChannel c) => YtChannelLogItem(
    at: at,
    icon: icon,
    color: color,
    text: text,
    note: note,
    isWatch: isWatch,
    channel: c,
    video: video,
  );
}

/// 把一個頻道的所有紀錄排成時間軸（新到舊）：
/// - 存起來的頻道事件（[YtChannelLogStore]）。
/// - 看影片：拿這個頻道的影片快取，對上「每支影片每次點開的時間」
///   （[YtVideoWatchStore]），一次點開一列。不在快取裡的影片對不到標題，
///   不會出現。
/// - 2026-10-06 開始記錄之前的舊頻道沒有「加入」事件，用頻道本身的
///   加入時間補一筆；目前已經刪除／永久刪除、卻沒有對應事件的，也用
///   頻道上的時間補。之前的換分類、還原這些查不回來，就不會有。
List<YtChannelLogItem> buildYtChannelLog({
  required YtChannel channel,
  required List<YtChannelEvent> events,
  required List<({YoutubeVideo video, List<DateTime> openedAt})> watched,
}) {
  bool has(YtChannelEventType t) => events.any((e) => e.type == t);
  final items = <YtChannelLogItem>[
    for (final e in events) _fromEvent(e),
    if (!has(YtChannelEventType.added))
      YtChannelLogItem(
        at: channel.addedAt,
        icon: Icons.add_circle_outline_rounded,
        color: AppColors.ok,
        text: channel.discoveredVia.isEmpty
            ? '加入'
            : '加入（挖掘：${channel.discoveredVia}）',
        isWatch: false,
      ),
    if (channel.deletedAt != null && !has(YtChannelEventType.deleted))
      YtChannelLogItem(
        at: channel.deletedAt!,
        icon: Icons.delete_outline_rounded,
        color: AppColors.bad,
        text: '刪除（移到垃圾桶）',
        isWatch: false,
      ),
    if (channel.purgedAt != null && !has(YtChannelEventType.purged))
      YtChannelLogItem(
        at: channel.purgedAt!,
        icon: Icons.delete_forever_outlined,
        color: AppColors.bad,
        text: '永久刪除',
        isWatch: false,
      ),
    for (final v in watched)
      for (final at in v.openedAt)
        YtChannelLogItem(
          at: at,
          icon: Icons.play_circle_outline_rounded,
          color: AppColors.accent,
          text: '看了「${v.video.title}」',
          isWatch: true,
          video: v.video,
        ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return items;
}

YtChannelLogItem _fromEvent(YtChannelEvent e) {
  final d = e.detail;
  final (
    IconData icon,
    Color color,
    String text,
    String? note,
  ) = switch (e.type) {
    YtChannelEventType.added => (
      Icons.add_circle_outline_rounded,
      AppColors.ok,
      d['revived'] == 'true'
          ? '手動新增，從永久刪除救回'
          : d['via'] != null
          ? '加入（挖掘：${d['via']}）'
          : '加入',
      d['category'] == null ? null : '分類「${d['category']}」',
    ),
    YtChannelEventType.moved => (
      Icons.drive_file_move_outline,
      AppColors.ink2,
      '從「${d['from']}」移到「${d['to']}」',
      d['reason'],
    ),
    YtChannelEventType.renamed => (
      Icons.edit_outlined,
      AppColors.ink2,
      '改名：${d['from']} → ${d['to']}',
      null,
    ),
    YtChannelEventType.pinned => (
      Icons.push_pin_rounded,
      AppColors.ytPinAccent,
      '置頂',
      null,
    ),
    YtChannelEventType.unpinned => (
      Icons.push_pin_outlined,
      AppColors.ytPinAccent,
      '取消置頂',
      null,
    ),
    YtChannelEventType.cold => (
      Icons.ac_unit_rounded,
      AppColors.ytColdAccent,
      '放進$ytColdSectionLabel',
      null,
    ),
    YtChannelEventType.uncold => (
      Icons.ac_unit_rounded,
      AppColors.ytColdAccent,
      '移出$ytColdSectionLabel',
      null,
    ),
    YtChannelEventType.deleted => (
      Icons.delete_outline_rounded,
      AppColors.bad,
      '刪除（移到垃圾桶）',
      null,
    ),
    YtChannelEventType.purged => (
      Icons.delete_forever_outlined,
      AppColors.bad,
      '永久刪除',
      null,
    ),
    YtChannelEventType.normal => (
      Icons.subscriptions_outlined,
      AppColors.ink2,
      '從待評鑑放到一般',
      null,
    ),
    YtChannelEventType.restored => (
      Icons.restore_from_trash_outlined,
      AppColors.ok,
      d['fromPurged'] == 'true' ? '從永久刪除還原' : '從垃圾桶還原',
      null,
    ),
  };
  return YtChannelLogItem(
    at: e.at,
    icon: icon,
    color: color,
    text: text,
    note: note,
    isWatch: false,
  );
}

/// 頻道紀錄頁（2026-10-06 使用者要求：每個頻道要有 log——什麼時候看了
/// 它哪支影片、什麼時候換分類、第一天加進來、刪除、永久刪除、還原……）。
/// 從頻道詳情頁右上角「紀錄」進來。
///
/// [channelId] 是 null 時是「全部頻道的紀錄」（2026-10-06 使用者要求：
/// 要有一份不限單一頻道的，放在 YT 首頁跟分類頁）：每一列多標出是哪個
/// 頻道、點一下進那個頻道。從分類頁進來會帶 [categoryIds]，預設只看
/// 那幾個分類的頻道，可以切回全部分類。
class YtChannelLogPage extends ConsumerStatefulWidget {
  const YtChannelLogPage({
    super.key,
    this.channelId,
    this.categoryIds = const {},
  });

  final String? channelId;
  final Set<String> categoryIds;

  @override
  ConsumerState<YtChannelLogPage> createState() => _YtChannelLogPageState();
}

enum _Filter { all, watch, channel }

typedef _LogData = ({
  YtChannel? channel,
  List<YtChannelLogItem> items,
  List<YtCategory> categories,
});

class _YtChannelLogPageState extends ConsumerState<YtChannelLogPage> {
  late final Future<_LogData> _future = _load();
  _Filter _filter = _Filter.all;

  /// 從分類頁進來時，要不要只看那幾個分類（預設要）。
  bool _onlySelected = true;

  bool get _global => widget.channelId == null;

  Future<_LogData> _load() async {
    final kv = ref.read(keyValueStoreProvider);
    final repo = ref.read(ytTrackerRepositoryProvider);
    final channels = await repo.channelsForUpload();
    final categories = await repo.loadCategories();
    if (_global) {
      final events = await YtChannelLogStore(kv).loadAll();
      final watchRecords = await YtVideoWatchStore(kv).loadAll();
      final cache = YtVideoCacheStore(kv);
      final items = <YtChannelLogItem>[];
      for (final c in channels) {
        final cached = await cache.load(c.id);
        items.addAll(
          buildYtChannelLog(
            channel: c,
            events: [
              for (final e in events)
                if (e.channelId == c.id) e,
            ],
            watched: [
              for (final v in cached)
                if (watchRecords[v.videoId] case final r?)
                  (video: v, openedAt: r.openedAt),
            ],
          ).map((i) => i.withChannel(c)),
        );
      }
      items.sort((a, b) => b.at.compareTo(a.at));
      return (channel: null, items: items, categories: categories);
    }
    final match = channels.where((c) => c.id == widget.channelId);
    if (match.isEmpty) {
      return (
        channel: null,
        items: <YtChannelLogItem>[],
        categories: categories,
      );
    }
    final channel = match.first;
    final events = await YtChannelLogStore(kv).forChannel(channel.id);
    final cached = await YtVideoCacheStore(kv).load(channel.id);
    final watchRecords = await YtVideoWatchStore(kv).loadAll();
    final watched = [
      for (final v in cached)
        if (watchRecords[v.videoId] case final r?)
          (video: v, openedAt: r.openedAt),
    ];
    return (
      channel: channel,
      items: buildYtChannelLog(
        channel: channel,
        events: events,
        watched: watched,
      ),
      categories: categories,
    );
  }

  String _title(_LogData? data) {
    if (!_global) {
      return data?.channel == null ? '頻道紀錄' : '${data!.channel!.name} 的紀錄';
    }
    return '全部頻道的紀錄';
  }

  /// 「只看這個分類」那顆的字。
  String _categoryLabel(List<YtCategory> categories) {
    final ids = widget.categoryIds;
    if (ids.length == 1) {
      if (ids.single == ytUncategorizedId) return '只看未分類';
      final match = categories.where((c) => c.id == ids.single);
      if (match.isNotEmpty) return '只看「${match.first.name}」';
    }
    return '只看選的 ${ids.length} 個分類';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppSideDrawer(),
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screenSide),
            child: FutureBuilder(
              future: _future,
              builder: (context, snap) {
                final data = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Gap.sm),
                    AppTopBar(
                      title: _title(data),
                      titleIcon: Icons.history_rounded,
                      titleIconColor: AppColors.ytAccent,
                      showSettings: false,
                    ),
                    const SizedBox(height: Gap.sm),
                    if (data == null)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      )
                    else ...[
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final (f, label) in const [
                            (_Filter.all, '全部'),
                            (_Filter.watch, '觀看紀錄'),
                            (_Filter.channel, '頻道異動'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _filter == f,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          if (_global && widget.categoryIds.isNotEmpty)
                            FilterChip(
                              label: Text(_categoryLabel(data.categories)),
                              selected: _onlySelected,
                              showCheckmark: false,
                              onSelected: (v) =>
                                  setState(() => _onlySelected = v),
                            ),
                        ],
                      ),
                      const SizedBox(height: Gap.sm),
                      Expanded(child: _timeline(data.items)),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeline(List<YtChannelLogItem> all) {
    final byCategory =
        _global && widget.categoryIds.isNotEmpty && _onlySelected;
    final items = [
      for (final i in all)
        if ((_filter == _Filter.all ||
                (_filter == _Filter.watch) == i.isWatch) &&
            (!byCategory ||
                widget.categoryIds.contains(
                  i.channel?.categoryId ?? ytUncategorizedId,
                )))
          i,
    ];
    if (items.isEmpty) {
      return const SingleChildScrollView(
        child: InlineEmptyCard(title: '還沒有紀錄', message: '換個篩選看看'),
      );
    }
    final rows = <Widget>[];
    String? lastDay;
    for (final i in items) {
      final day = '${i.at.year}/${i.at.month}/${i.at.day}';
      if (day != lastDay) {
        lastDay = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, Gap.md, 0, Gap.xs),
            child: Text(day, style: AppText.note),
          ),
        );
      }
      rows.add(_Row(item: i));
    }
    // 全部頻道的紀錄可能很長（每支看過的影片每次點開都一列），用
    // builder 只畫看得到的那幾列，不一次全部建出來。
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (_, i) => rows[i],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final YtChannelLogItem item;

  @override
  Widget build(BuildContext context) {
    final channel = item.channel;
    final row = _content();
    // 觀看紀錄的影片列自己會處理點擊（開影片），不用再包一層。
    if (channel == null || item.video != null) return row;
    // 全部頻道的紀錄：點一下進那個頻道的詳情頁。
    return InkWell(
      onTap: () => context.push('/yt-tracker/channel/${channel.id}'),
      child: row,
    );
  }

  Widget _content() {
    String two(int n) => n.toString().padLeft(2, '0');
    final channel = item.channel;
    final video = item.video;
    if (video != null) {
      // 觀看紀錄：左邊觀看時間，右邊跟影片清單一樣的影片列（點了照樣能
      // 開來看、往左滑一樣有按鈕）。
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              width: 42,
              child: Text(
                '${two(item.at.hour)}:${two(item.at.minute)}',
                style: AppText.note,
              ),
            ),
          ),
          Expanded(
            child: YtVideoRow(
              key: ValueKey(
                '${video.videoId}-${item.at.microsecondsSinceEpoch}',
              ),
              video: video,
              subtitle: channel == null
                  ? ytRelativeTime(video.publishedAt)
                  : '${channel.name}・${ytRelativeTime(video.publishedAt)}',
              forceShow: true,
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '${two(item.at.hour)}:${two(item.at.minute)}',
              style: AppText.note,
            ),
          ),
          Icon(item.icon, size: 17, color: item.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (channel != null)
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink2,
                    ),
                  ),
                Text(
                  item.text,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
                if (item.note != null) Text(item.note!, style: AppText.note),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

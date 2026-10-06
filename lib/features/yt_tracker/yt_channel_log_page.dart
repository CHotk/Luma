import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_channel_log_store.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../domain/models/yt_tracker.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/app_side_drawer.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/inline_empty_card.dart';

/// 時間軸上的一列。
class YtChannelLogItem {
  const YtChannelLogItem({
    required this.at,
    required this.icon,
    required this.color,
    required this.text,
    this.note,
    required this.isWatch,
  });

  final DateTime at;
  final IconData icon;
  final Color color;
  final String text;
  final String? note;

  /// 看影片的紀錄（篩選「只看影片」用）。
  final bool isWatch;
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
  required List<({String title, List<DateTime> openedAt})> watched,
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
          text: '看了「${v.title}」',
          isWatch: true,
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
class YtChannelLogPage extends ConsumerStatefulWidget {
  const YtChannelLogPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<YtChannelLogPage> createState() => _YtChannelLogPageState();
}

enum _Filter { all, watch, channel }

class _YtChannelLogPageState extends ConsumerState<YtChannelLogPage> {
  late final Future<({YtChannel? channel, List<YtChannelLogItem> items})>
  _future = _load();
  _Filter _filter = _Filter.all;

  Future<({YtChannel? channel, List<YtChannelLogItem> items})> _load() async {
    final kv = ref.read(keyValueStoreProvider);
    final channels = await ref
        .read(ytTrackerRepositoryProvider)
        .channelsForUpload();
    final match = channels.where((c) => c.id == widget.channelId);
    if (match.isEmpty) return (channel: null, items: <YtChannelLogItem>[]);
    final channel = match.first;
    final events = await YtChannelLogStore(kv).forChannel(channel.id);
    final cached = await YtVideoCacheStore(kv).load(channel.id);
    final watchRecords = await YtVideoWatchStore(kv).loadAll();
    final watched = [
      for (final v in cached)
        if (watchRecords[v.videoId] case final r?)
          (title: v.title, openedAt: r.openedAt),
    ];
    return (
      channel: channel,
      items: buildYtChannelLog(
        channel: channel,
        events: events,
        watched: watched,
      ),
    );
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
                      title: data?.channel == null
                          ? '頻道紀錄'
                          : '${data!.channel!.name} 的紀錄',
                      titleIcon: Icons.history_rounded,
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
                            (_Filter.watch, '看影片'),
                            (_Filter.channel, '頻道異動'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _filter == f,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _filter = f),
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
    final items = [
      for (final i in all)
        if (_filter == _Filter.all || (_filter == _Filter.watch) == i.isWatch)
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
    return ListView(
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final YtChannelLogItem item;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
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

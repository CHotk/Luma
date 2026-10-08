import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../data/repositories/yt_video_cache_store.dart';
import '../../domain/models/fitness.dart';
import '../../data/repositories/yt_video_watch_store.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/track_switcher.dart';
import '../jp_home/jp_home_controller.dart';

/// 今日儀表板要顯示的數字，一次算好。每一項各自算、各自容錯：某個功能
/// 讀資料失敗就那一格顯示「讀不到」，不讓整個首頁壞掉。
class AppHomeDashboardData {
  const AppHomeDashboardData({
    required this.enRoundsDone,
    required this.enRoundsPerDay,
    required this.jpTodayCount,
    required this.jpTarget,
    required this.diaryToday,
    required this.fitnessLast,
    required this.ytNewVideos,
    required this.lastSyncedAt,
    required this.syncConfigured,
  });

  final int? enRoundsDone;
  final int? enRoundsPerDay;

  /// 日文今天練了幾題（手寫練習＋考試）。
  final int? jpTodayCount;
  final int? jpTarget;

  /// 今天寫了幾篇日記，null＝讀不到。
  final int? diaryToday;

  /// 最近一次健身打卡：什麼時候、練什麼。null＝從沒打過卡或讀不到。
  final ({DateTime at, String type})? fitnessLast;

  /// 本機影片快取裡，近 24 小時發布、還沒看過的影片數（不打 API）。
  final int? ytNewVideos;

  final DateTime? lastSyncedAt;
  final bool syncConfigured;
}

/// 看 [dataRevisionProvider]：任何功能寫入資料後回到首頁，數字會重算。
final appHomeDashboardProvider =
    FutureProvider.autoDispose<AppHomeDashboardData>((ref) async {
      ref.watch(dataRevisionProvider);
      final now = DateTime.now();
      bool isToday(DateTime d) =>
          d.year == now.year && d.month == now.month && d.day == now.day;

      Future<T?> safe<T>(Future<T> Function() f) async {
        try {
          return await f();
        } catch (_) {
          return null;
        }
      }

      final settings = ref.read(settingsRepositoryProvider);
      final usage = await safe(() => settings.loadUsage(now));
      final rules = await safe(settings.loadRules);
      final jp = await safe(() => ref.watch(jpHomeStateProvider.future));
      final diaryToday = await safe(() async {
        final entries = await ref.read(diaryRepositoryProvider).loadAll();
        return entries.where((e) => isToday(e.savedAt)).length;
      });
      final fitnessLast = await safe(() async {
        final entries = await ref.read(fitnessRepositoryProvider).loadEntries();
        if (entries.isEmpty) return null;
        final last = entries.reduce(
          (a, b) => a.loggedAt.isAfter(b.loggedAt) ? a : b,
        );
        return (at: last.loggedAt, type: last.type.label);
      });
      final ytNew = await safe(() async {
        final kv = ref.read(keyValueStoreProvider);
        final channels = await ref
            .read(ytTrackerRepositoryProvider)
            .loadChannels();
        final watched = (await YtVideoWatchStore(kv).loadAll()).keys.toSet();
        final cache = YtVideoCacheStore(kv);
        final since = now.subtract(const Duration(hours: 24));
        var count = 0;
        for (final c in channels) {
          for (final v in await cache.load(c.id)) {
            if (v.publishedAt.isAfter(since) && !watched.contains(v.videoId)) {
              count++;
            }
          }
        }
        return count;
      });
      final lastSyncRaw = await safe(
        () => ref.read(keyValueStoreProvider).read('r2_sync.last_synced_at.v1'),
      );

      return AppHomeDashboardData(
        enRoundsDone: usage?.roundsDone,
        enRoundsPerDay: rules?.roundsPerDay,
        jpTodayCount: jp?.todayCount,
        jpTarget: jp?.config.dailyKanaTarget,
        diaryToday: diaryToday,
        fitnessLast: fitnessLast,
        ytNewVideos: ytNew,
        lastSyncedAt: lastSyncRaw == null
            ? null
            : DateTime.tryParse(lastSyncRaw),
        syncConfigured: ref.read(r2CredentialsProvider) != null,
      );
    });

/// App 首頁的「今日儀表板」樣式（設計稿 `已選擇完成/首頁設計/02_今日儀表板`，
/// 2026-10-05 使用者要求做出來當預設）：最上面一張大的英文進度卡，下面
/// 四格日文／日記／健身／YT，最後一張同步狀態；點卡片進那個功能。
/// 儀表板沒放到的功能（看盤、抽菸、喝酒）收在最下面一排小按鈕。
class AppHomeDashboard extends ConsumerWidget {
  const AppHomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appHomeDashboardProvider);
    final d = async.valueOrNull;
    if (d == null) {
      return async.hasError
          ? Text('讀不到今天的資料：${async.error}', style: AppText.bodyDim)
          : const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
    }

    final enDone = d.enRoundsDone;
    final enTotal = d.enRoundsPerDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashCard(
          label: '🇬🇧 英文',
          accent: AppColors.accent,
          highlight: true,
          onTap: () => context.go(LearningTrack.en.homeRoute),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                enDone == null || enTotal == null
                    ? '讀不到'
                    : enDone >= enTotal
                    ? '今天的份量做完了'
                    : '今天 $enDone / $enTotal 輪',
                style: const TextStyle(fontSize: 22, color: AppColors.ink),
              ),
              if (enDone != null && enTotal != null && enTotal > 0) ...[
                const SizedBox(height: Gap.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: (enDone / enTotal).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    backgroundColor: AppColors.glassEdge,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Gap.md,
          crossAxisSpacing: Gap.md,
          childAspectRatio: 1.6,
          children: [
            _DashCard(
              label: '🇯🇵 日文',
              accent: AppColors.jpAccent,
              onTap: () => context.go(LearningTrack.ja.homeRoute),
              child: _Big(
                d.jpTodayCount == null
                    ? '讀不到'
                    : d.jpTodayCount == 0
                    ? '今天還沒練'
                    : '今天練了 ${d.jpTodayCount} 題',
              ),
            ),
            _DashCard(
              label: '📔 日記',
              accent: AppColors.diaryAccent,
              onTap: () => context.go('/diary'),
              child: _Big(
                d.diaryToday == null
                    ? '讀不到'
                    : d.diaryToday == 0
                    ? '今天還沒寫'
                    : '今天寫了 ${d.diaryToday} 篇',
                color: d.diaryToday == 0 ? AppColors.diaryAccent : null,
              ),
            ),
            _DashCard(
              label: '💪 健身',
              accent: const Color(0xFFF2A65A),
              onTap: () => context.go('/fitness'),
              child: _Big(_fitnessText(d.fitnessLast)),
            ),
            _DashCard(
              label: '▶ YT',
              accent: AppColors.ytAccent,
              onTap: () => context.go('/yt-tracker'),
              child: _Big(
                d.ytNewVideos == null
                    ? '讀不到'
                    : d.ytNewVideos == 0
                    ? '沒有新影片'
                    : '${d.ytNewVideos} 支新影片',
                color: (d.ytNewVideos ?? 0) > 0 ? AppColors.ytAccent : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        _DashCard(
          label: '☁ 同步',
          accent: const Color(0xFF7ED6D0),
          onTap: () => context.go('/sync'),
          child: Text(
            !d.syncConfigured
                ? '還沒設定雲端同步'
                : d.lastSyncedAt == null
                ? '還沒同步過'
                : '${_ago(d.lastSyncedAt!)}同步過',
            style: const TextStyle(fontSize: 14, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text('其他', style: AppText.note),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, route) in const [
              ('交易&自律', '/crypto-watch'),
              ('負債管理', '/debt'),
              ('抽菸記錄', '/smoking-log'),
              ('喝酒記錄', '/drinking-log'),
              ('本機儲存', '/local-storage'),
              ('除錯', '/debug-log'),
            ])
              ActionChip(
                label: Text(label),
                onPressed: () => context.go(route),
                backgroundColor: AppColors.glassFill,
                side: const BorderSide(color: AppColors.glassEdge),
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.ink2,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _fitnessText(({DateTime at, String type})? last) {
  if (last == null) return '還沒打過卡';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(last.at.year, last.at.month, last.at.day);
  final days = today.difference(day).inDays;
  final when = switch (days) {
    0 => '今天',
    1 => '昨天',
    _ => '$days 天前',
  };
  return '$when練了${last.type}';
}

String _ago(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';
  return '${diff.inDays} 天前';
}

class _Big extends StatelessWidget {
  const _Big(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 16.5, color: color ?? AppColors.ink),
    );
  }
}

class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.label,
    required this.accent,
    required this.onTap,
    required this.child,
    this.highlight = false,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  /// 最上面那張大卡片用強調色外框。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final card = GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: AppText.note),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    if (!highlight) return card;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: card,
    );
  }
}

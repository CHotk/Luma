import '../../data/services/youtube_api_service.dart';

/// 頻道詳情頁「簡介」分頁的數字（2026-10-15 使用者要求簡介豐富一點）。
/// 全部從本機影片快取算，不多打 API；快取還沒抓完整個頻道時，數字是
/// 「目前抓到的這些」。純 Dart，方便測試。
class YtChannelStats {
  YtChannelStats._({
    required this.total,
    required this.regular,
    required this.shorts,
    required this.live,
    required this.avgDuration,
    required this.first,
    required this.latest,
    required this.perMonth,
    required this.weekdays,
    required this.slots,
    required this.top,
    required this.totalViews,
    required this.watched,
    required this.lastWatched,
  });

  /// 時段：凌晨 0–6、早上 6–12、下午 12–18、晚上 18–24。
  static const slotLabels = ['凌晨', '早上', '下午', '晚上'];
  static const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  final int total;
  final int regular;
  final int shorts;
  final int live;
  final Duration? avgDuration;
  final DateTime? first;
  final DateTime? latest;

  /// 從第一部到現在，平均每月幾部。
  final double? perMonth;

  /// 星期一～日各發幾部（index 0＝星期一）。
  final List<int> weekdays;

  /// 四個時段各發幾部，見 [slotLabels]。
  final List<int> slots;

  /// 觀看次數最多的幾部（有觀看次數的才算）。
  final List<YoutubeVideo> top;

  /// 抓到的影片觀看次數加總；一部都沒有觀看次數是 null。
  final int? totalViews;

  /// 看過幾部、最近一次看是什麼時候。
  final int watched;
  final DateTime? lastWatched;

  int? get busiestWeekday => _maxIndex(weekdays);
  int? get busiestSlot => _maxIndex(slots);

  static int? _maxIndex(List<int> l) {
    var best = -1, at = -1;
    for (var i = 0; i < l.length; i++) {
      if (l[i] > best) (best, at) = (l[i], i);
    }
    return best <= 0 ? null : at;
  }

  factory YtChannelStats.from(
    List<YoutubeVideo> all, {
    required int? Function(YoutubeVideo) viewsOf,
    required DateTime? Function(String videoId) lastWatchedOf,
    DateTime? now,
    int topCount = 3,
  }) {
    final n = now ?? DateTime.now();
    final videos = [
      for (final v in all)
        if (v.removedAt == null) v,
    ];
    final durations = [
      for (final v in videos)
        if (v.duration case final d? when d > Duration.zero) d,
    ];
    final dates = [for (final v in videos) v.publishedAt]..sort();
    final weekdays = List.filled(7, 0);
    final slots = List.filled(4, 0);
    for (final d in dates) {
      final l = d.toLocal();
      weekdays[l.weekday - 1]++;
      slots[l.hour ~/ 6]++;
    }
    double? perMonth;
    if (dates.isNotEmpty) {
      final months = n.difference(dates.first).inDays / 30.44;
      perMonth = months < 1 ? dates.length.toDouble() : dates.length / months;
    }
    final withViews = [
      for (final v in videos)
        if (viewsOf(v) != null) v,
    ]..sort((a, b) => viewsOf(b)!.compareTo(viewsOf(a)!));
    var watched = 0;
    DateTime? lastWatched;
    for (final v in all) {
      final t = lastWatchedOf(v.videoId);
      if (t == null) continue;
      watched++;
      if (lastWatched == null || t.isAfter(lastWatched)) lastWatched = t;
    }
    return YtChannelStats._(
      total: videos.length,
      regular: videos
          .where((v) => v.isShort == false && v.isLive == false)
          .length,
      shorts: videos.where((v) => v.isShort == true).length,
      live: videos.where((v) => v.isLive == true).length,
      avgDuration: durations.isEmpty
          ? null
          : Duration(
              seconds:
                  durations.fold(0, (s, d) => s + d.inSeconds) ~/
                  durations.length,
            ),
      first: dates.isEmpty ? null : dates.first,
      latest: dates.isEmpty ? null : dates.last,
      perMonth: perMonth,
      weekdays: weekdays,
      slots: slots,
      top: withViews.take(topCount).toList(),
      totalViews: withViews.isEmpty
          ? null
          : withViews.fold<int>(0, (s, v) => s + viewsOf(v)!),
      watched: watched,
      lastWatched: lastWatched,
    );
  }
}

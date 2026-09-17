/// 首頁頂端列「週幾 時:分 emoji」要用的純邏輯，英文／日文首頁共用，
/// 不要各刻一份。純 Dart，不碰 Flutter，才能直接單元測試。
const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayLabel(DateTime date) => '週${_weekdayLabels[date.weekday - 1]}';

String clockLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

/// 五個時段各配一個不同的 emoji（使用者 2026-09-17 要求）。邊界照常見
/// 的中文時段習慣抓：凌晨 00–05、早上 06–10、中午 11–13、下午 14–17、
/// 晚上 18–23。
String periodEmoji(DateTime date) {
  final h = date.hour;
  if (h < 6) return '🌙';
  if (h < 11) return '🌅';
  if (h < 14) return '☀️';
  if (h < 18) return '🌤️';
  return '🌆';
}

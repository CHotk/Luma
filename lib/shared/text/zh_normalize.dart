import 'zh_pairs.dart';

Map<String, String>? _t2s;

Map<String, String> get _map {
  final cached = _t2s;
  if (cached != null) return cached;
  final runes = traditionalToSimplifiedPairs.runes.toList();
  final map = <String, String>{};
  for (var i = 0; i + 1 < runes.length; i += 2) {
    map[String.fromCharCode(runes[i])] = String.fromCharCode(runes[i + 1]);
  }
  return _t2s = map;
}

/// 把繁體字轉成簡體字，其他字元不動。
String toSimplified(String text) {
  final map = _map;
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(map[ch] ?? ch);
  }
  return buffer.toString();
}

/// 搜尋比對用：兩邊都轉成簡體＋小寫再比，簡繁怎麼打都找得到
/// （2026-09-24 使用者要求：搜尋不要簡繁分開）。
bool zhContains(String haystack, String needle) => toSimplified(
  haystack,
).toLowerCase().contains(toSimplified(needle).toLowerCase());

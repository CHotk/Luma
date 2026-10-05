import 'dart:convert';

import 'package:flutter/material.dart';

/// 本機儲存裡的一個 key：多大、幾筆。
class StorageKeyInfo {
  const StorageKeyInfo({
    required this.key,
    required this.bytes,
    required this.count,
  });

  final String key;

  /// key＋內容實際佔的位元組（UTF-8）。
  final int bytes;

  /// 內容是 JSON 陣列就是幾筆、物件就是幾個欄位；不是 JSON（純文字設定
  /// 值）就是 null，畫面顯示「—」。
  final int? count;
}

/// 「大小排行」的一列：一個功能底下的所有 key 加總。
class StorageGroup {
  const StorageGroup({
    required this.label,
    required this.color,
    required this.keys,
  });

  final String label;
  final Color color;

  /// 依大小由大到小。
  final List<StorageKeyInfo> keys;

  int get bytes => keys.fold(0, (sum, k) => sum + k.bytes);
}

/// key 開頭 → 屬於哪個功能。由上往下比，先對到的算（所以比較細的放
/// 前面，例如 YT 影片快取要排在「YT 其他」前面）。都對不到的歸「其他
/// 設定」。
const _rules = <(String prefix, String label, Color color)>[
  ('kana.practice.', '日文練習', Color(0xFFEA92AC)),
  ('kana.exam.', '日文考試', Color(0xFFEA92AC)),
  ('history.', '英文作答紀錄', Color(0xFF7EA6FF)),
  ('words.', '英文單字庫', Color(0xFF7EA6FF)),
  ('yt_tracker.video_cache', 'YT 影片快取', Color(0xFFFF2D40)),
  ('yt_tracker.subscriber_history.', 'YT 訂閱數紀錄', Color(0xFFFF2D40)),
  ('yt_tracker.video_resume.', 'YT 翻頁位置', Color(0xFFFF2D40)),
  ('yt_tracker.video_watch', 'YT 看過／隱藏', Color(0xFFFF2D40)),
  ('yt_tracker.video_hidden', 'YT 看過／隱藏', Color(0xFFFF2D40)),
  ('yt_tracker.', 'YT 頻道與設定', Color(0xFFFF2D40)),
  ('diary.', '日記', Color(0xFF8FBF9F)),
  ('fitness.', '健身', Color(0xFFF2A65A)),
  ('crypto_watch.', '看盤記錄', Color(0xFFF5C763)),
  ('smoking.', '抽菸記錄', Color(0xFFB0A8A0)),
  ('drinking.', '喝酒記錄', Color(0xFFE0607E)),
  ('r2_sync.log', '同步紀錄', Color(0xFF7ED6D0)),
  ('r2_sync.meta.', '同步比對資料', Color(0xFF7ED6D0)),
  ('r2_sync.', '雲端同步設定', Color(0xFF7ED6D0)),
  ('debug.', '除錯紀錄', Color(0xFFFF938B)),
];

const _otherLabel = '其他設定';
const _otherColor = Color(0xFF8B8BA3);

/// 含金鑰、密碼的 key：「本機儲存」頁只顯示大小，不顯示內容——這頁可以
/// 直接看到 JSON，金鑰不該就這樣攤在畫面上。日記內容另外有密碼鎖，
/// 這裡也不開放看，不然等於繞過日記的密碼。
bool isSensitiveStorageKey(String key) =>
    key == 'r2_sync.credentials.v1' ||
    key == 'yt_tracker.api_key.v1' ||
    key.startsWith('diary.');

/// 把整份本機儲存依功能分組，組跟組之間、組內的 key 都依大小由大到小。
List<StorageGroup> groupStorage(Map<String, String> all) {
  final byLabel = <String, (Color, List<StorageKeyInfo>)>{};
  for (final MapEntry(:key, :value) in all.entries) {
    var label = _otherLabel;
    var color = _otherColor;
    for (final (prefix, l, c) in _rules) {
      if (key.startsWith(prefix)) {
        label = l;
        color = c;
        break;
      }
    }
    final info = StorageKeyInfo(
      key: key,
      bytes: utf8.encode(key).length + utf8.encode(value).length,
      count: _countOf(value),
    );
    byLabel.putIfAbsent(label, () => (color, [])).$2.add(info);
  }
  final groups = [
    for (final MapEntry(key: label, value: (color, keys)) in byLabel.entries)
      StorageGroup(
        label: label,
        color: color,
        keys: keys..sort((a, b) => b.bytes.compareTo(a.bytes)),
      ),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
  return groups;
}

int? _countOf(String value) {
  final trimmed = value.trimLeft();
  if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) return decoded.length;
    if (decoded is Map) return decoded.length;
  } catch (_) {
    // 看起來像 JSON 但解析不了，就當成沒有筆數。
  }
  return null;
}

/// 位元組換成好讀的大小，例如 14.2 MB、612 KB、9 B。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

/// JSON 內容最多顯示幾個字。整份五十音練習筆畫可能十幾 MB，全部畫出來
/// 畫面會卡死，超過就只顯示前面這麼多，並註明總長。
const storagePreviewChars = 20000;

/// 把 key 的內容整理成要顯示的文字：是 JSON 就排版縮排（太大的不排版，
/// 直接截前面一段），不是 JSON 就原樣。回傳顯示用文字跟有沒有被截斷。
({String text, bool truncated, int totalChars}) previewStorageValue(
  String value,
) {
  var text = value;
  // 太大的排版本身就很慢，超過 2MB 就不排版，直接截。
  if (value.length <= 2 * 1024 * 1024) {
    try {
      text = const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {
      text = value;
    }
  }
  final truncated = text.length > storagePreviewChars;
  return (
    text: truncated ? text.substring(0, storagePreviewChars) : text,
    truncated: truncated,
    totalChars: text.length,
  );
}

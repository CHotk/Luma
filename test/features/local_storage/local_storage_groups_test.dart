import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/features/local_storage/local_storage_groups.dart';

void main() {
  test('依功能分組、由大到小排，YT 影片快取每個頻道一個 key 會加總成一組', () {
    final groups = groupStorage({
      'kana.practice.entries.v1': jsonEncode([
        for (var i = 0; i < 50; i++) {'strokes': 'x' * 200},
      ]),
      'yt_tracker.video_cache.ch1.v1': jsonEncode([1, 2, 3]),
      'yt_tracker.video_cache.ch2.v1': jsonEncode([4, 5]),
      'yt_tracker.channels.v1': jsonEncode([]),
      'track.last': 'jp',
    });

    expect(groups.first.label, '日文練習');
    expect(groups.first.keys.single.count, 50);
    final ytCache = groups.firstWhere((g) => g.label == 'YT 影片快取');
    expect(ytCache.keys.map((k) => k.key), hasLength(2));
    expect(groups.map((g) => g.label), contains('YT 頻道與設定'));
    final other = groups.firstWhere((g) => g.label == '其他設定');
    expect(other.keys.single.count, isNull);
    for (var i = 1; i < groups.length; i++) {
      expect(groups[i - 1].bytes, greaterThanOrEqualTo(groups[i].bytes));
    }
  });

  test('含金鑰、密碼、日記的 key 不顯示內容', () {
    expect(isSensitiveStorageKey('r2_sync.credentials.v1'), isTrue);
    expect(isSensitiveStorageKey('yt_tracker.api_key.v1'), isTrue);
    expect(isSensitiveStorageKey('diary.entries.v1'), isTrue);
    expect(isSensitiveStorageKey('fitness.entries.v1'), isFalse);
  });

  test('大小好讀', () {
    expect(formatBytes(9), '9 B');
    expect(formatBytes(612 * 1024), '612 KB');
    expect(formatBytes((14.2 * 1024 * 1024).round()), '14.2 MB');
  });

  test('JSON 會排版；太長的只顯示前面一段並註明', () {
    final small = previewStorageValue('{"a":1}');
    expect(small.text, contains('\n  "a": 1'));
    expect(small.truncated, isFalse);

    final big = previewStorageValue(jsonEncode(['x' * 30000]));
    expect(big.truncated, isTrue);
    expect(big.text.length, storagePreviewChars);
  });
}

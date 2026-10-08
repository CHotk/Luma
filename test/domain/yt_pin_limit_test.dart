import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/yt_tracker.dart';

/// 2026-10-08 使用者要求：每個分類最多置頂 10 個頻道。
YtChannel ch(
  String id, {
  String? cat,
  bool pinned = false,
  bool trashed = false,
}) => YtChannel.fromJson({
  'id': id,
  'name': id,
  'categoryId': cat,
  'avatarEmoji': '📺',
  'avatarImageUrl': '',
  'url': '',
  'description': '',
  'addedAt': '2026-10-01T00:00:00.000',
  if (pinned) 'pinnedAt': '2026-10-02T00:00:00.000',
  if (trashed) 'deletedAt': '2026-10-03T00:00:00.000',
});

void main() {
  test('只算同一個分類、已置頂、沒進垃圾桶的，不算自己', () {
    final list = [
      for (var i = 0; i < 9; i++) ch('a$i', cat: 'A', pinned: true),
      ch('a-trash', cat: 'A', pinned: true, trashed: true),
      ch('a-normal', cat: 'A'),
      ch('b1', cat: 'B', pinned: true),
      ch('none', pinned: true),
    ];
    expect(ytPinnedCountIn(list, 'A'), 9);
    expect(ytPinnedCountIn(list, 'A', exceptId: 'a0'), 8);
    expect(ytPinnedCountIn(list, 'B'), 1);
    expect(ytPinnedCountIn(list, null), 1);
    expect(ytMaxPinnedPerCategory, 10);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/yt_tracker.dart';

/// 歌手頻道（2026-10-15）：標了跟著頻道存、同步，可以取消。
void main() {
  test('標成歌手存得進去、讀得回來，取消後是 null', () {
    final c = YtChannel(
      id: 'a',
      name: '周杰倫',
      categoryId: 'music',
      addedAt: DateTime(2026),
    );
    expect(c.isArtist, isFalse);
    final marked = c.copyWith(artistAt: DateTime(2026, 10, 15));
    final back = YtChannel.fromJson(marked.toJson());
    expect(back.isArtist, isTrue);
    expect(back.artistAt, DateTime(2026, 10, 15));
    expect(back.copyWith(artistAt: null).isArtist, isFalse);
    // 改別的欄位不會把歌手標記弄掉。
    expect(back.copyWith(name: '周董').isArtist, isTrue);
  });
}

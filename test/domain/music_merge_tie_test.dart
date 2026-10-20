import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/models/music.dart';

void main() {
  // 2026-10-20：手機用舊版 App 讀了電腦新增的歌手，大頭貼沒讀進來、時間卻一樣；
  // 合併時要讓有大頭貼那份贏，而且算成「有下載」。
  test('時間相同、內容不同：資料多的那份贏', () {
    final t = DateTime.utc(2026, 10, 19, 9);
    final bare = MusicArtist(id: 'a1', name: '王靖雯', updatedAt: t);
    final full = bare.copyWith(avatarUrls: ['https://x/1.jpg']);
    final phone = MusicData.empty.putArtist(bare);
    final cloud = MusicData.empty.putArtist(full);
    final merged = MusicData.merge(phone, cloud);
    expect(merged.artist('a1')!.avatarUrls, ['https://x/1.jpg']);
    expect(phone.newerIn(merged), 1);
    expect(cloud.newerIn(merged), 0);
    expect(MusicData.merge(cloud, phone).artist('a1')!.avatarUrls.length, 1);
  });
}

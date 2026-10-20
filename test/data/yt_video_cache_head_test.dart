import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_video_cache_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';

class _Mem implements KeyValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// 頻道詳情先秀快取最前面幾部（2026-10-20）：只解析前面一段也要讀得對。
void main() {
  test('只讀前面 N 部：是最新的 N 部，標題裡有括號、引號、跳脫字元也不會讀錯', () async {
    final store = _Mem();
    await YtVideoCacheStore(store).upsertVideos('c', [
      for (var i = 0; i < 300; i++)
        YoutubeVideo(
          videoId: 'v$i',
          title: '第 $i 部 {"怪"} [標題] \ 結尾',
          publishedAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
          thumbnailUrl: '',
        ),
    ]);
    // 換一個新的 store 物件、清掉記憶體那份不行（記憶體照底層儲存記），
    // 所以直接用另一個假儲存放同一份文字，模擬剛開 App 還沒讀過整份。
    final fresh = _Mem()..data.addAll(store.data);
    final head = await YtVideoCacheStore(fresh).loadHead('c', 200);
    expect(head.length, 200);
    expect(head.first.videoId, 'v299');
    expect(head.last.videoId, 'v100');
    expect(head.first.title, '第 299 部 {"怪"} [標題] \ 結尾');
    // 不到 N 部就全部。
    expect((await YtVideoCacheStore(fresh).loadHead('c', 999)).length, 300);
    // 沒有快取。
    expect(await YtVideoCacheStore(fresh).loadHead('none', 200), isEmpty);
  });
}

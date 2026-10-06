import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_channel_log_store.dart';

// 2026-10-06：原本寫 `nextInt(1 << 32)`，網頁版位元運算只有 32 位，
// `1 << 32` 變成 0、`nextInt(0)` 直接丟錯，記頻道紀錄就炸。電腦上 VM 跑
// 是 64 位測不出來，要用 `flutter test --platform chrome` 跑這支才抓得到。
void main() {
  test('產生紀錄 id 不會丟錯，而且每次都不一樣', () {
    final ids = {for (var i = 0; i < 200; i++) YtChannelLogStore.newId()};
    expect(ids.length, 200);
  });
}

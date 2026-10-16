import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_video_song_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

/// 音樂分類標「歌曲」（2026-10-16）。
void main() {
  test('同步合併：同一部比改的時間，後改的贏（取消也會傳過去）', () {
    final t1 = DateTime(2026, 10, 1), t2 = DateTime(2026, 10, 2);
    final a = {'x': (song: true, at: t1), 'y': (song: true, at: t2)};
    final b = {'x': (song: false, at: t2), 'z': (song: true, at: t1)};
    final m = YtVideoSongStore.merge(a, b);
    expect(m['x']!.song, isFalse);
    expect(m['y']!.song, isTrue);
    expect(m['z']!.song, isTrue);
  });

  Future<(_MemoryStore, ProviderContainer)> pump(
    WidgetTester tester, {
    required bool songMode,
  }) async {
    final store = _MemoryStore();
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                YtVideoRow(
                  video: YoutubeVideo(
                    videoId: 'v1',
                    title: '一首歌',
                    publishedAt: DateTime(2026, 1, 1),
                    thumbnailUrl: '',
                  ),
                  subtitle: '',
                  songMode: songMode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (store, container);
  }

  testWidgets('音樂分類：往左滑有「歌曲」，按了標起來、存檔、再按取消', (tester) async {
    final (store, container) = await pump(tester, songMode: true);
    await tester.timedDrag(
      find.text('一首歌'),
      const Offset(-120, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲'));
    await tester.pumpAndSettle();
    expect(container.read(ytVideoSongsProvider), {'v1'});
    expect(await YtVideoSongStore(store).loadIds(), {'v1'});
    expect(find.byTooltip('歌曲'), findsOneWidget); // 縮圖上的 ♪

    await tester.timedDrag(
      find.text('一首歌'),
      const Offset(-120, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消歌曲'));
    await tester.pumpAndSettle();
    expect(container.read(ytVideoSongsProvider), isEmpty);
    expect(await YtVideoSongStore(store).loadIds(), isEmpty);
  });

  testWidgets('不是音樂分類：沒有「歌曲」鈕', (tester) async {
    await pump(tester, songMode: false);
    await tester.timedDrag(
      find.text('一首歌'),
      const Offset(-120, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('歌曲'), findsNothing);
    expect(find.text('隱藏'), findsOneWidget);
  });
}

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/nav_bar_prefs_store.dart';
import 'package:lume/data/repositories/yt_playlist_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_playlists_page.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';
import 'package:lume/shared/widgets/floating_tab_bar.dart';

/// 2026-10-14：播放清單（設計稿第 1 版）＋底部浮動膠囊分頁列。
void main() {
  YoutubeVideo video(String id) => YoutubeVideo(
    videoId: id,
    title: '影片 $id',
    publishedAt: DateTime(2026, 10, 1),
    thumbnailUrl: '',
  );
  YtPlaylist pl(String id, DateTime at, {List<String> ids = const []}) =>
      YtPlaylist(
        id: id,
        name: id,
        items: [
          for (final v in ids)
            YtPlaylistItem(video: video(v), channelName: '頻道', addedAt: at),
        ],
        createdAt: DateTime(2026),
        updatedAt: at,
      );

  test('合併：同一份清單後改的贏、刪掉的墓碑也算；稍後觀看一定在、排第一', () async {
    final a = [
      pl('fav', DateTime(2026, 10, 2), ids: ['x']),
      pl('old', DateTime(2026, 10, 1)),
    ];
    final b = [
      pl('fav', DateTime(2026, 10, 1), ids: ['y']),
      pl(
        'old',
        DateTime(2026, 10, 3),
      ).copyWith(deletedAt: DateTime(2026, 10, 3)),
      pl('new', DateTime(2026, 10, 3)),
    ];
    final merged = YtPlaylistStore.merge(a, b);
    expect(merged.firstWhere((p) => p.id == 'fav').items.single.videoId, 'x');
    expect(merged.firstWhere((p) => p.id == 'old').deletedAt, isNotNull);
    final store = YtPlaylistStore(_MemoryStore());
    await store.saveAll(merged);
    final visible = YtPlaylistStore.visible(await store.loadAll());
    expect(visible.first.isLater, isTrue);
    expect(visible.map((p) => p.id), isNot(contains('old')));
    expect(visible.map((p) => p.id), containsAll(['fav', 'new']));
  });

  test('底部分頁列設定：預設全 App 共用，存了記住', () async {
    final s = NavBarPrefsStore(_MemoryStore());
    expect((await s.load()).mode, NavBarMode.global);
    await s.save(NavBarPrefs.defaults.copyWith(mode: NavBarMode.feature));
    expect((await s.load()).mode, NavBarMode.feature);
  });

  testWidgets('影片 ⋮ →「存到稍後觀看」：清單多一部、影片下面標已存在', (tester) async {
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
            body: YtVideoRow(
              video: video('a'),
              subtitle: '1 天前',
              channelId: 'ch',
              channelName: '頻道A',
              known: (watched: null, hidden: false),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存到稍後觀看'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final later = container
        .read(ytPlaylistsProvider)
        .firstWhere((p) => p.isLater);
    expect(later.items.single.videoId, 'a');
    expect(later.items.single.channelName, '頻道A');
    expect(find.text('≡ 已存在：稍後觀看'), findsOneWidget);
    // 本機也存了。
    final saved = await tester.runAsync(() => YtPlaylistStore(store).loadAll());
    expect(saved!.firstWhere((p) => p.isLater).items, hasLength(1));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('播放清單頁：封面卡片、點進去列出影片', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(_MemoryStore()),
        ytPlaylistsProvider.overrideWith(
          (ref) => [
            YtPlaylist.emptyLater(),
            pl('fav', DateTime(2026, 10, 2), ids: ['x', 'y']),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: YtPlaylistsPage()),
      ),
    );
    await tester.pump();
    expect(find.text('稍後觀看'), findsOneWidget);
    expect(find.text('2 部影片'), findsOneWidget);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: YtPlaylistPage(playlistId: 'fav')),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('影片 x', findRichText: true), findsOneWidget);
    expect(find.textContaining('影片 y', findRichText: true), findsOneWidget);
  });

  testWidgets('浮動膠囊：點了換分頁；縮起來只剩一格，點它展開', (tester) async {
    var tapped = -1;
    var expanded = false;
    const tabs = [
      FloatingTab(icon: Icons.abc, selectedIcon: Icons.abc, label: '頻道'),
      FloatingTab(icon: Icons.abc, selectedIcon: Icons.abc, label: '影片'),
      FloatingTab(icon: Icons.abc, selectedIcon: Icons.abc, label: '播放清單'),
    ];
    Widget bar({required bool collapsed}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: FloatingTabBar(
            tabs: tabs,
            selected: 1,
            collapsed: collapsed,
            onTap: (i) => tapped = i,
            onExpand: () => expanded = true,
          ),
        ),
      ),
    );
    await tester.pumpWidget(bar(collapsed: false));
    await tester.tap(find.text('播放清單'));
    expect(tapped, 2);

    await tester.pumpWidget(bar(collapsed: true));
    await tester.pumpAndSettle();
    expect(find.text('播放清單'), findsNothing);
    await tester.tap(find.text('影片'));
    expect(expanded, isTrue);
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

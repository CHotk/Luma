import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/data/repositories/yt_video_rating_store.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_browse_page.dart';

import '../../support/poke.dart';
import '../../support/yt_fake.dart';

/// YT 分類頁的流程（2026-11-12 補到 95%）：頻道 ⋮ 泡泡選單每個動作（置頂、一般、
/// 冷藏、移動（取消／選分類）、編輯、刪除、標成／取消歌手、垃圾桶的還原／永久刪除）、
/// 排序（訂閱多→少／少→多／準度）、搜尋影片（有結果、找不到、清掉）、刪除分類、
/// 挖掘分類的來源標籤、幣圈分類的準度統計、訂閱數用 @帳號更新。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  Finder bubble() => find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('_BubbleMenuHost'),
  );

  Finder moreOf(WidgetTester tester, String name) {
    final rows = find.ancestor(of: find.text(name), matching: find.byType(Row));
    for (final e in rows.evaluate()) {
      final f = find.descendant(
        of: find.byElementPredicate((x) => x == e),
        matching: find.byTooltip('更多'),
      );
      if (f.evaluate().isNotEmpty) return f.first;
    }
    throw StateError('找不到「$name」的 ⋮');
  }

  Future<(MemoryStore, FakeYoutube)> open(
    WidgetTester tester,
    Set<String> ids, {
    bool trash = false,
    Future<void> Function(MemoryStore)? extra,
  }) async {
    final store = MemoryStore();
    await seedYt(tester, store);
    if (extra != null) await tester.runAsync(() => extra(store));
    final yt = FakeYoutube();
    await http.runWithClient(() async {
      await pumpPage(
        tester,
        store,
        () => YtTrackerBrowsePage(initialCategoryIds: ids, trash: trash),
        size: const Size(390, 1400),
        overrides: [ytApiKeyProvider.overrideWith((_) => 'KEY')],
      );
      await settle(tester, 6);
    }, yt.client);
    return (store, yt);
  }

  Future<void> act(
    WidgetTester tester,
    FakeYoutube yt,
    String channel,
    String item,
  ) => http.runWithClient(() async {
    // 冷藏區預設收起來，先展開。
    while (find.text('展開').evaluate().isNotEmpty) {
      await tester.tap(find.text('展開').first);
      await settle(tester, 2);
    }
    final more = moreOf(tester, channel);
    await tester.ensureVisible(more);
    await tester.tap(more);
    await settle(tester, 3);
    await tester.tap(find.descendant(of: bubble(), matching: find.text(item)));
    await settle(tester, 4);
  }, yt.client);

  Future<YtChannel> ch(WidgetTester tester, MemoryStore s, String id) async =>
      (await tester.runAsync(
        () => YtTrackerRepository(s).channelsForUpload(),
      ))!.firstWhere((c) => c.id == id);

  testWidgets('泡泡選單：置頂、一般、冷藏、移動（取消、選音樂）、編輯、刪除（取消、確定）', (tester) async {
    final (store, yt) = await open(tester, {'c1'});
    await act(tester, yt, '頻道b', '置頂');
    expect((await ch(tester, store, 'b')).pinnedAt, isNotNull);
    expect((await ch(tester, store, 'b')).coldAt, isNull);
    await act(tester, yt, '頻道a', ytColdSectionLabel);
    expect((await ch(tester, store, 'a')).coldAt, isNotNull);
    await act(tester, yt, '頻道a', '一般');
    expect((await ch(tester, store, 'a')).coldAt, isNull);
    await act(tester, yt, '頻道r', '一般');
    expect((await ch(tester, store, 'r')).pendingReview, isFalse);

    await act(tester, yt, '頻道r', '移動');
    expect(find.text('「頻道r」移到…'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    await act(tester, yt, '頻道r', '移動');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('音樂')),
    );
    await settle(tester, 4);
    expect((await ch(tester, store, 'r')).categoryId, 'c2');

    await act(tester, yt, '頻道b', '編輯');
    expect(find.text('route:/yt-tracker/channel/b'), findsOneWidget);
  });

  testWidgets('泡泡選單：刪除（取消、確定）；移到未分類', (tester) async {
    final (store, yt) = await open(tester, {'c1'});
    await act(tester, yt, '頻道a', '刪除');
    expect(find.text('刪除「頻道a」？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    expect((await ch(tester, store, 'a')).deletedAt, isNull);
    await act(tester, yt, '頻道a', '刪除');
    await tester.tap(find.text('刪除').last);
    await settle(tester, 4);
    expect((await ch(tester, store, 'a')).deletedAt, isNotNull);
    await act(tester, yt, '頻道b', '移動');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('未分類')),
    );
    await settle(tester, 4);
    expect((await ch(tester, store, 'b')).categoryId, isNull);
  });

  testWidgets('音樂分類：取消歌手、標成歌手', (tester) async {
    final (store, yt) = await open(tester, {'c2'});
    await act(tester, yt, '頻道m', '取消歌手');
    expect((await ch(tester, store, 'm')).isArtist, isFalse);
    await act(tester, yt, '頻道m', '標成歌手');
    expect((await ch(tester, store, 'm')).isArtist, isTrue);
  });

  testWidgets('垃圾桶：還原；永久刪除（取消、確定）', (tester) async {
    final (store, yt) = await open(
      tester,
      {'c1'},
      trash: true,
      extra: (s) async {
        final repo = YtTrackerRepository(s);
        await repo.deleteChannel('b');
      },
    );
    await act(tester, yt, '頻道t', '還原');
    expect((await ch(tester, store, 't')).deletedAt, isNull);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await act(tester, yt, '頻道b', '永久刪除');
    await tester.tap(find.text('取消'));
    await settle(tester, 3);
    expect((await ch(tester, store, 'b')).purgedAt, isNull);
    await act(tester, yt, '頻道b', '永久刪除');
    await tester.tap(find.text('永久刪除').last);
    await settle(tester, 4);
    expect((await ch(tester, store, 'b')).purgedAt, isNotNull);
  });

  testWidgets('排序：訂閱人數多→少、少→多、預設', (tester) async {
    final (_, yt) = await open(
      tester,
      {'c1'},
      extra: (s) async {
        final repo = YtTrackerRepository(s);
        final now = DateTime.now();
        for (final (id, subs) in [('s1', 5), ('s2', null), ('s3', 900000)]) {
          await repo.addChannel(
            YtChannel(
              id: id,
              name: '頻道$id',
              categoryId: 'c1',
              youtubeChannelId: 'UC$id',
              uploadsPlaylistId: 'UU$id',
              url: '',
              addedAt: now,
              subscriberCount: subs,
              reviewedAt: now,
              statsUpdatedAt: now,
            ),
          );
        }
      },
    );
    await http.runWithClient(() async {
      for (final label in ['訂閱人數 多→少', '訂閱人數 少→多', '預設排序']) {
        await tester.tap(find.text(label));
        await settle(tester, 2);
      }
    }, yt.client);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜尋這些頻道的影片：有結果、找不到、清掉、收起', (tester) async {
    final (_, yt) = await open(tester, {'c1'});
    await http.runWithClient(() async {
      await tester.tap(find.byTooltip('搜尋這些頻道的影片'));
      await settle(tester, 3);
      expect(find.text('打字就會搜這些頻道抓過的全部影片'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '影片 1');
      await settle(tester, 4);
      expect(find.textContaining('找到'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '沒有這部');
      await settle(tester, 4);
      expect(find.text('抓過的影片裡找不到「沒有這部」'), findsOneWidget);
      await tester.tap(find.byTooltip('收起搜尋'));
      await settle(tester, 3);
    }, yt.client);
    expect(find.text('打字就會搜這些頻道抓過的全部影片'), findsNothing);
  });

  testWidgets('刪除分類：從分類頁按垃圾桶鈕', (tester) async {
    final (store, yt) = await open(tester, {'c2'});
    await http.runWithClient(() async {
      await tester.tap(find.byTooltip('刪除分類'));
      await settle(tester, 4);
      await tester.tap(find.widgetWithText(TextButton, '刪除'));
      await settle(tester, 6);
    }, yt.client);
    final cats = (await tester.runAsync(
      () => YtTrackerRepository(store).loadCategories(),
    ))!;
    expect(cats.any((c) => c.id == 'c2'), isFalse);
  });

  testWidgets('挖掘分類：卡片右上角有來源；泡泡選單沒有置頂／一般／冷藏', (tester) async {
    final (_, yt) = await open(
      tester,
      {ytDiscoverCategoryId},
      extra: (s) async {
        final repo = YtTrackerRepository(s);
        await repo.addCategory(
          const YtCategory(
            id: ytDiscoverCategoryId,
            name: '挖掘新頻道',
            colorValue: 0xFF7EA6FF,
          ),
        );
        await repo.addChannel(
          YtChannel(
            id: 'd1',
            name: '挖到的',
            categoryId: ytDiscoverCategoryId,
            youtubeChannelId: '',
            url: 'https://www.youtube.com/@dug',
            addedAt: DateTime.now(),
            discoveredVia: '露營',
          ),
        );
      },
    );
    expect(find.text('露營'), findsOneWidget);
    await http.runWithClient(() async {
      await tester.tap(moreOf(tester, '挖到的'));
      await settle(tester, 3);
    }, yt.client);
    expect(
      find.descendant(of: bubble(), matching: find.text('置頂')),
      findsNothing,
    );
    await tester.tapAt(const Offset(4, 4));
    await settle(tester, 2);
    // 沒有頻道 ID 的用 @帳號問了訂閱數。
    expect(yt.calls.any((u) => u.queryParameters['forHandle'] != null), isTrue);
  });

  testWidgets('幣圈分類：準度排序、準度統計鈕', (tester) async {
    final now = DateTime.now();
    final (_, yt) = await open(
      tester,
      {'c3'},
      extra: (s) async {
        final repo = YtTrackerRepository(s);
        await repo.addCategory(
          const YtCategory(id: 'c3', name: '幣圈', colorValue: 0xFFFFC857),
        );
        for (final id in ['k1', 'k2', 'k3']) {
          await repo.addChannel(
            YtChannel(
              id: id,
              name: '幣$id',
              categoryId: 'c3',
              youtubeChannelId: 'UC$id',
              uploadsPlaylistId: 'UU$id',
              url: '',
              addedAt: now,
              reviewedAt: now,
              statsUpdatedAt: now,
            ),
          );
        }
        final rs = YtVideoRatingStore(s);
        for (var i = 0; i < 12; i++) {
          await rs.set(
            'x$i',
            YtVideoRating(
              at: now,
              verdict: i.isEven ? YtVerdict.ok : YtVerdict.bad,
              ratedAt: now,
              channelId: i < 8 ? 'k1' : 'k2',
            ),
          );
        }
      },
    );
    await http.runWithClient(() async {
      await tester.tap(find.text('🎯 準度 高→低'));
      await settle(tester, 2);
      await tester.tap(find.byTooltip('準度統計'));
      await settle(tester, 3);
    }, yt.client);
    expect(tester.takeException(), isNull);
  });
}

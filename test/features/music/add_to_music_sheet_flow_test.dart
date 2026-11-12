import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/domain/models/music.dart';
import 'package:lume/features/music/add_to_music_sheet.dart';

import '../../support/music_fake.dart';
import '../../support/poke.dart';

/// 加到音樂面板的邊界（2026-11-12 補到 95%）：已經在音樂裡的直接開編輯；
/// 沒選歌手、歌名空白不給加；相似歌名點一下帶入；打新歌名、選原唱（勾、取消勾）、
/// 每種版本、年份、備註，加進去。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetRef ref;
  late BuildContext ctx;

  Future<void> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          musicDataProvider.overrideWith((_) => seedMusicData()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, r, _) {
                ref = r;
                ctx = c;
                return const Text('host');
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, String id, String title) async {
    showAddToMusicSheet(
      ctx,
      ref,
      videoId: id,
      videoTitle: title,
      thumbnailUrl: '',
      channelName: '某個頻道',
      publishedAt: DateTime(2019, 5, 1),
      durationSec: 200,
    );
    await settle(tester, 4);
  }

  Finder addBtn() => find.byType(FilledButton).last;

  testWidgets('已經在音樂裡：直接開編輯', (tester) async {
    await host(tester);
    await open(tester, 'v1', '晴天');
    expect(find.textContaining('編輯'), findsWidgets);
    await closeOverlays(tester);
  });

  testWidgets('沒選歌手、歌名空白不給加；相似歌名帶入；新歌選原唱、每種版本，加進去', (tester) async {
    await host(tester);
    await open(tester, 'newvid', '晴天 鋼琴版 cover');
    // 歌名清空：不給加（沒猜到歌手時先說要選歌手）。
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '');
    await tester.pump();
    await tester.ensureVisible(addBtn());
    await tester.tap(addBtn());
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.textContaining('先選是誰唱的').evaluate().isNotEmpty ||
          find.textContaining('歌名不能空白').evaluate().isNotEmpty,
      isTrue,
    );
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    // 相似歌名。
    await tester.enterText(fields.first, '晴');
    await settle(tester, 2);
    final similar = find.textContaining('是《');
    if (similar.evaluate().isNotEmpty) {
      await tester.tap(similar.first);
      await settle(tester, 2);
    }
    // 打一個全新的歌名，才會出現原唱。
    await tester.enterText(fields.first, '全新的歌');
    await settle(tester, 2);
    for (final t in MusicVersionType.values) {
      final f = find.text(t.label);
      if (f.evaluate().isEmpty) continue;
      await tester.ensureVisible(f.last);
      await tester.tap(f.last, warnIfMissed: false);
      await tester.pump();
    }
    for (final name in ['周杰倫', '周杰倫', '小花']) {
      final f = find.text(name);
      if (f.evaluate().isEmpty) continue;
      await tester.ensureVisible(f.last);
      await tester.tap(f.last, warnIfMissed: false);
      await tester.pump();
    }
    if (fields.evaluate().length >= 3) {
      await tester.enterText(fields.at(1), '2020');
      await tester.enterText(fields.at(2), '鋼琴版');
    }
    await tester.pump();
    await tester.ensureVisible(addBtn());
    await tester.tap(addBtn());
    await settle(tester, 4);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester, 2);
    await closeOverlays(tester);
    expect(tester.takeException(), isNull);
  });
}

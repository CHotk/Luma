import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/features/yt_tracker/yt_duration_filter.dart';

/// 時長膠囊與小選單（2026-11-12 補到 95%）：預設區間選完就收、每項旁的數字、
/// 自訂展開拉桿（拉的當下就套、兩顆不能疊）、點外面收起、膠囊在畫面右邊或左邊
/// 選單都不會跑出畫面；自訂 0–40+ 等於不限、時長 0 秒不算。
void main() {
  YoutubeVideo v(int? s) => YoutubeVideo(
    videoId: 'v$s',
    title: 't',
    publishedAt: DateTime(2026, 10, 1),
    thumbnailUrl: '',
    duration: s == null ? null : Duration(seconds: s),
  );
  final videos = [v(30), v(100), v(200), v(500), v(1500), v(3000), v(null)];
  int countOf(YtDurationFilter f) => videos.where(f.matches).length;

  test('自訂 0–40+ 等於不限；0 秒的不算；標籤', () {
    const all = YtDurationFilter.custom(0, 40);
    expect(videos.every(all.matches), isTrue);
    const some = YtDurationFilter.custom(1, 10);
    expect(some.matches(v(0)), isFalse);
    expect(some.matches(v(null)), isFalse);
    expect(YtDurationFilter.customLabel(0, 40), '不限');
    expect(const YtDurationFilter.any().chipLabel, '時長');
    expect(YtDurationFilter.preset(YtDurationPreset.custom).isAny, isFalse);
    expect(YtDurationFilter.preset(YtDurationPreset.any).isAny, isTrue);
    for (final p in YtDurationPreset.values) {
      expect(YtDurationFilter.preset(p).rangeLabel, isNotEmpty);
    }
  });

  Future<List<YtDurationFilter>> pump(
    WidgetTester tester, {
    YtDurationFilter initial = const YtDurationFilter.any(),
    Alignment align = Alignment.topRight,
  }) async {
    final changes = <YtDurationFilter>[];
    var filter = initial;
    tester.view.physicalSize = const Size(390, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, set) => Align(
              alignment: align,
              child: YtDurationChip(
                filter: filter,
                countOf: countOf,
                onChanged: (f) => set(() {
                  filter = f;
                  changes.add(f);
                }),
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(YtDurationChip));
    await tester.pumpAndSettle();
  }

  testWidgets('預設區間：每項旁有數字、選完就收、膠囊改成區間', (tester) async {
    final changes = await pump(tester);
    expect(find.text('時長'), findsOneWidget);
    await openMenu(tester);
    // 不限 7、2 分內 2、2–6 分 2（200、… 100 不算）、6–20 分 1。
    expect(find.text('7'), findsOneWidget);
    await tester.tap(find.text('2–6 分'));
    await tester.pumpAndSettle();
    expect(changes.single.preset, YtDurationPreset.from2to6);
    expect(find.text('2–6 分'), findsOneWidget); // 膠囊
    expect(find.text('不限'), findsNothing); // 選單收了
    // 再打開：選中的打勾；選回不限。
    await openMenu(tester);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('不限'));
    await tester.pumpAndSettle();
    expect(find.text('時長'), findsOneWidget);
  });

  testWidgets('自訂：展開拉桿、拉了就套、兩顆不能疊、點外面收起', (tester) async {
    final changes = await pump(
      tester,
      initial: YtDurationFilter.preset(YtDurationPreset.from6to20),
    );
    await openMenu(tester);
    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();
    // 從目前選的 6–20 帶過去。
    expect(find.text('6–20 分'), findsWidgets);
    expect(find.textContaining('符合'), findsOneWidget);
    expect(find.text('40+ 分'), findsOneWidget);
    expect(changes.last.preset, YtDurationPreset.custom);

    final slider = find.byType(RangeSlider);
    final box = tester.getRect(slider);
    // 拖左邊那顆往右（20 分的地方），拉桿上的字跟著變。
    await tester.dragFrom(
      Offset(box.left + 24 + (box.width - 48) * 6 / 40, box.center.dy),
      Offset((box.width - 48) * 4 / 40, 0),
    );
    await tester.pumpAndSettle();
    expect(changes.last.minMinutes, greaterThan(6));
    // 用 onChanged 直接試「疊在一起」：不接受。
    final rs = tester.widget<RangeSlider>(slider);
    final n = changes.length;
    rs.onChanged!(const RangeValues(10, 10.4));
    await tester.pump();
    expect(changes.length, n);
    rs.onChanged!(const RangeValues(0, 40));
    await tester.pump();
    expect(changes.last.isAny, isFalse);
    expect(find.text('不限'), findsWidgets);

    // 點外面收起，留著最後的條件。
    await tester.tapAt(const Offset(20, 800));
    await tester.pumpAndSettle();
    expect(find.byType(RangeSlider), findsNothing);
    expect(changes.last.preset, YtDurationPreset.custom);
  });

  testWidgets('一開始就是自訂：拉桿直接展開；膠囊在左邊選單也不跑出畫面', (tester) async {
    await pump(
      tester,
      initial: const YtDurationFilter.custom(3, 40),
      align: Alignment.topLeft,
    );
    expect(find.text('3–40+ 分'), findsOneWidget);
    await openMenu(tester);
    expect(find.byType(RangeSlider), findsOneWidget);
    final menu = tester.getRect(find.byType(RangeSlider));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });
}

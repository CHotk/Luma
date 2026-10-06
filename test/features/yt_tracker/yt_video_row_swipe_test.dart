import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

const _title = '測試影片標題';

Future<void> _pumpRow(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(_MemoryStore())],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              YtVideoRow(
                video: YoutubeVideo(
                  videoId: 'v1',
                  title: _title,
                  publishedAt: DateTime(2026, 10, 1),
                  thumbnailUrl: '',
                ),
                subtitle: '1 天前',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _titleX(WidgetTester tester) => tester.getTopLeft(find.text(_title)).dx;

void main() {
  // 2026-10-05 使用者回報：往左滑要很大力或很遠才露出按鈕。
  testWidgets('往左拖一小段（約 40px）放手就打開', (tester) async {
    await _pumpRow(tester);
    final before = _titleX(tester);

    await tester.timedDrag(
      find.text(_title),
      const Offset(-45, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(before - _titleX(tester), closeTo(156, 1));
  });

  testWidgets('輕甩一下也算，就算只滑了一點點', (tester) async {
    await _pumpRow(tester);
    final before = _titleX(tester);

    await tester.fling(find.text(_title), const Offset(-30, 0), 800);
    await tester.pumpAndSettle();

    expect(before - _titleX(tester), closeTo(156, 1));
  });

  testWidgets('只碰一下、拖很短不會誤開', (tester) async {
    await _pumpRow(tester);
    final before = _titleX(tester);

    await tester.timedDrag(
      find.text(_title),
      const Offset(-20, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(_titleX(tester), closeTo(before, 1));
  });

  // 2026-10-06 使用者要求改成 iOS 原生／LINE 那種：滑開後露出圓角按鈕，
  // 點得到；拉過頭放手會彈回原本的寬度。
  testWidgets('滑開露出「紀錄」「隱藏」，拉過頭放手彈回原寬度', (tester) async {
    await _pumpRow(tester);
    final before = _titleX(tester);

    await tester.timedDrag(
      find.text(_title),
      const Offset(-260, 0),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();

    expect(before - _titleX(tester), closeTo(156, 1));
    expect(find.text('紀錄'), findsOneWidget);
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

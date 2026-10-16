import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_display_prefs_store.dart';
import 'package:lume/data/repositories/yt_video_watch_store.dart';
import 'package:lume/data/services/youtube_api_service.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/yt_tracker/yt_video_row.dart';

/// 影片 NEW（2026-10-16 使用者要求）：發布 N 天內（設定可調，預設 7）、
/// 還沒點開看過才標。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Duration age,
    bool watched = false,
    int? days,
  }) async {
    final store = _MemoryStore();
    if (watched) await YtVideoWatchStore(store).markOpened('v1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          if (days != null)
            ytDisplayPrefsProvider.overrideWith(
              (ref) => YtDisplayPrefs.defaults.copyWith(newBadgeDays: days),
            ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                YtVideoRow(
                  video: YoutubeVideo(
                    videoId: 'v1',
                    title: '測試影片',
                    publishedAt: DateTime.now().subtract(age),
                    thumbnailUrl: '',
                  ),
                  subtitle: '',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('20 小時前發布、沒看過 → NEW', (tester) async {
    await pump(tester, age: const Duration(hours: 20));
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('看過了 → 不標', (tester) async {
    await pump(tester, age: const Duration(hours: 20), watched: true);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('8 天前 → 預設 7 天，不標', (tester) async {
    await pump(tester, age: const Duration(days: 8));
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('設定改 14 天 → 8 天前的也標', (tester) async {
    await pump(tester, age: const Duration(days: 8), days: 14);
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('設定「不標」 → 都不標', (tester) async {
    await pump(tester, age: const Duration(hours: 1), days: 0);
    expect(find.text('NEW'), findsNothing);
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

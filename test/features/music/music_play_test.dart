import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/music_play_log_store.dart';
import 'package:lume/data/repositories/music_play_mode_store.dart';
import 'package:lume/data/storage/key_value_store.dart';
import 'package:lume/features/music/music_play.dart';
import 'package:lume/features/music/music_player.dart';

/// 音樂播放方式跟播放紀錄（2026-10-19）。
void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    MusicPlayMode mode,
    void Function(BuildContext, WidgetRef) onTap,
  ) async {
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(_MemoryStore()),
        musicPlayModeProvider.overrideWith((ref) => mode),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => onTap(context, ref),
              child: const Text('播'),
            ),
          ),
        ),
      ),
    );
    return c;
  }

  testWidgets('預設轉到 YouTube：記一筆紀錄，App 內播放器不動', (tester) async {
    expect(MusicPlayModeStore.defaultMode, MusicPlayMode.youtube);
    final c = await pump(
      tester,
      MusicPlayMode.youtube,
      (ctx, ref) => musicPlay(ctx, ref, ['a', 'b', 'c'], 'b'),
    );
    await tester.tap(find.text('播'));
    await tester.pumpAndSettle();
    expect(c.read(musicPlayLogProvider)['b'], hasLength(1));
    expect(c.read(musicPlayerProvider).current, isNull);
    final saved = await MusicPlayLogStore(c.read(keyValueStoreProvider)).load();
    expect(saved['b'], hasLength(1));
  });

  testWidgets('App 內播放：每首開始播都記（含下一首）', (tester) async {
    final c = await pump(
      tester,
      MusicPlayMode.embedded,
      (ctx, ref) => musicPlay(ctx, ref, ['a', 'b'], 'a'),
    );
    await tester.tap(find.text('播'));
    await tester.pumpAndSettle();
    final p = c.read(musicPlayerProvider);
    expect(p.current, 'a');
    p.next();
    await tester.pumpAndSettle();
    final log = c.read(musicPlayLogProvider);
    expect(log['a'], hasLength(1));
    expect(log['b'], hasLength(1));
  });

  test('播放紀錄合併是聯集，同一個時間不重複', () {
    final t1 = DateTime.utc(2026, 10, 1), t2 = DateTime.utc(2026, 10, 2);
    final m = MusicPlayLogStore.merge(
      {'a': [t1]},
      {'a': [t1, t2], 'b': [t2]},
    );
    expect(m['a'], [t1, t2]);
    expect(m['b'], [t2]);
    expect(MusicPlayLogStore.count(m), 3);
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/music_play_log_store.dart';
import '../../data/repositories/music_play_mode_store.dart';
import '../yt_tracker/yt_video_row.dart' show openExternalUrl;
import 'music_player.dart';

/// 記一筆播放紀錄（2026-10-19）：一筆都不刪。[from] 從哪裡點的，[mode]
/// 'youtube' 或 'app'。
Future<void> recordMusicPlay(
  T Function<T>(ProviderListenable<T>) read,
  String videoId, {
  required String from,
  required String mode,
}) async {
  final play = MusicPlay(at: DateTime.now(), from: from, mode: mode);
  final log = read(musicPlayLogProvider);
  final next = {
    ...log,
    videoId: [...?log[videoId], play],
  };
  read(musicPlayLogProvider.notifier).state = next;
  await MusicPlayLogStore(read(keyValueStoreProvider)).save(next);
}

/// 音樂所有「播」的入口都走這裡（2026-10-19）：照設定轉到 YouTube（預設）
/// 或用 App 裡的播放器。[queue] 是整份清單，從 [id] 開始；[shuffle] 是隨機；
/// [from] 是從哪裡點的（記進播放紀錄）。
///
/// 轉到 YouTube 時，好幾首就用 YouTube 的臨時播放清單
/// （`watch_videos?video_ids=`，最多 50 首）帶過去，到那邊也會一首接一首。
Future<void> musicPlay(
  BuildContext context,
  WidgetRef ref,
  List<String> queue,
  String id, {
  required String from,
  bool shuffle = false,
}) async {
  final src = shuffle ? '$from・隨機' : from;
  if (ref.read(musicPlayModeProvider) == MusicPlayMode.embedded) {
    final player = ref.read(musicPlayerProvider);
    if (shuffle) {
      player.shuffleAll(queue.isEmpty ? [id] : queue, from: src);
    } else {
      player.playList(queue, id, from: src);
    }
    return; // App 內播放：每首開始播時播放器自己記（見 [MusicPlayer.onStart]）
  }
  final q = queue.isEmpty ? [id] : queue;
  var order = shuffle
      ? (List.of(q)..shuffle(math.Random()))
      : [
          ...q.skip(math.max(0, q.indexOf(id))),
          ...q.take(math.max(0, q.indexOf(id))),
        ];
  if (order.isEmpty) order = [id];
  await recordMusicPlay(ref.read, order.first, from: src, mode: 'youtube');
  if (!context.mounted) return;
  final url = order.length == 1
      ? 'https://www.youtube.com/watch?v=${order.first}'
      : 'https://www.youtube.com/watch_videos?video_ids=${order.take(50).join(',')}';
  await openExternalUrl(context, url);
}

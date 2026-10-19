import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_play.dart' show recordMusicPlay;
import 'music_yt_bridge.dart';

/// 音樂播放器的狀態（2026-10-19）：佇列、播到哪、隨機、重複、展開沒。
/// 整個 App 一份（[musicPlayerProvider]），播放器畫面疊在最上層，換頁不中斷。
class MusicPlayer extends ChangeNotifier {
  MusicPlayer({this.onStart}) {
    bridge = MusicYtBridge(_onEvent);
  }

  /// 每一首開始播（含自動接下一首）時呼叫，拿來記播放紀錄：(影片 id, 從哪來)。
  final void Function(String videoId, String from)? onStart;

  /// 這份佇列是從哪裡點的（記播放紀錄用）。
  String source = '';

  /// 下一次開始播是怎麼來的（第一首＝[source]，之後是「自動接下一首」等）。
  String _reason = '';

  late final MusicYtBridge bridge;

  /// 播放佇列（版本 id＝影片 id）。
  List<String> queue = const [];
  int index = 0;
  bool playing = false;
  double position = 0;
  double duration = 0;
  bool shuffle = false;

  /// 0 不重複、1 重複整個佇列、2 重複這一首。
  int repeat = 0;

  /// 全螢幕播放器打開了沒。
  bool expanded = false;

  /// 看影片（大）還是只聽（影片縮小，YouTube 規定不能完全藏起來）。
  bool showVideo = true;

  String? get current => queue.isEmpty ? null : queue[index];

  /// 從 [list] 裡的 [id] 開始播；隨機開著就把其他的打散。
  void playList(List<String> list, String id, {String from = ''}) {
    source = from;
    _reason = from;
    final q = list.isEmpty ? [id] : list;
    if (shuffle) {
      final rest = q.where((x) => x != id).toList()..shuffle(math.Random());
      queue = [id, ...rest];
      index = 0;
    } else {
      queue = List.of(q);
      index = math.max(0, queue.indexOf(id));
    }
    _loadCurrent();
  }

  /// 隨機播一整份。
  void shuffleAll(List<String> list, {String from = ''}) {
    if (list.isEmpty) return;
    shuffle = true;
    playList(list, list[math.Random().nextInt(list.length)], from: from);
  }

  /// 下一首播放：插在現在這首後面。
  void playNext(String id) {
    if (current == null) {
      playList([id], id, from: '下一首播放');
      return;
    }
    final q = List.of(queue)..remove(id);
    final at = math.min(q.indexOf(current!) + 1, q.length);
    q.insert(at, id);
    queue = q;
    index = q.indexOf(current!);
    notifyListeners();
  }

  void _loadCurrent() {
    position = 0;
    duration = 0;
    playing = true;
    bridge.load(current!);
    onStart?.call(current!, _reason);
    notifyListeners();
  }

  void toggle() {
    if (current == null) return;
    playing ? bridge.pause() : bridge.play();
    playing = !playing;
    notifyListeners();
  }

  void next({bool auto = false}) {
    if (queue.isEmpty) return;
    if (auto && repeat == 2) {
      bridge.seek(0);
      bridge.play();
      return;
    }
    _reason = auto ? '$source・自動接下一首' : '$source・按下一首';
    if (index < queue.length - 1) {
      index++;
    } else if (repeat == 1 || !auto) {
      index = 0;
    } else {
      playing = false;
      notifyListeners();
      return;
    }
    _loadCurrent();
  }

  void prev() {
    if (queue.isEmpty) return;
    if (position > 3) {
      seek(0);
      return;
    }
    index = math.max(0, index - 1);
    _reason = '$source・按上一首';
    _loadCurrent();
  }

  void seek(double seconds) {
    bridge.seek(seconds);
    position = seconds;
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = (repeat + 1) % 3;
    notifyListeners();
  }

  void setExpanded(bool v) {
    expanded = v;
    notifyListeners();
  }

  void setShowVideo(bool v) {
    showVideo = v;
    notifyListeners();
  }

  /// 關掉播放器（停掉、清空佇列）。
  void close() {
    bridge.stop();
    queue = const [];
    index = 0;
    playing = false;
    expanded = false;
    notifyListeners();
  }

  /// 這首從音樂刪掉了：從佇列拿掉，正在播的就接下一首。
  void removeFromQueue(String id) {
    if (!queue.contains(id)) return;
    final wasCurrent = current == id;
    final q = List.of(queue)..remove(id);
    if (q.isEmpty) {
      close();
      return;
    }
    queue = q;
    index = math.min(index, q.length - 1);
    if (wasCurrent) {
      _loadCurrent();
    } else {
      notifyListeners();
    }
  }

  void _onEvent(int? state, double? time, double? dur) {
    var changed = false;
    if (time != null && (time - position).abs() >= 0.5) {
      position = time;
      changed = true;
    }
    if (dur != null && dur > 0 && dur != duration) {
      duration = dur;
      changed = true;
    }
    if (state != null) {
      if (state == 0) {
        next(auto: true);
        return;
      }
      final p = state == 1 || state == 3;
      if (state == 1 || state == 2) {
        if (p != playing) {
          playing = p;
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    bridge.dispose();
    super.dispose();
  }
}

final musicPlayerProvider = ChangeNotifierProvider<MusicPlayer>(
  (ref) => MusicPlayer(
    onStart: (id, from) =>
        recordMusicPlay(ref.read, id, from: from, mode: 'app'),
  ),
);

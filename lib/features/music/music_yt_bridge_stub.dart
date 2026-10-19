import 'package:flutter/material.dart';

/// 非網頁平台的退回版本（這個 App 實際上只有網頁版在跑）。
class MusicYtBridge {
  MusicYtBridge(this.onEvent);

  /// (狀態, 目前秒數, 總秒數)。狀態照 YouTube：-1 未開始、0 播完、1 播放中、
  /// 2 暫停、3 緩衝、5 已載入。
  final void Function(int? state, double? time, double? duration) onEvent;

  Widget view() => const Center(
    child: Text('這個平台不支援內嵌播放', style: TextStyle(color: Colors.white70)),
  );
  void load(String videoId) {}
  void play() {}
  void pause() {}
  void seek(double seconds) {}
  void stop() {}
  void dispose() {}
}

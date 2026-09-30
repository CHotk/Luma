import 'package:flutter/material.dart';

/// 非網頁平台的退回版本——這個 App 實際上只有網頁版在跑，這份純粹是
/// 讓非網頁平台也編譯得過（跟 `external_link_stub.dart` 同一個理由：
/// `dart:html`／`dart:ui_web` 在非網頁平台編譯不過）。
Widget buildYtEmbeddedPlayer(String videoId) => const Center(
  child: Text('這個平台不支援內嵌播放', style: TextStyle(color: Colors.white70)),
);

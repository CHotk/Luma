// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// YouTube 官方開放的內嵌播放器格式（`youtube.com/embed/<id>`），本來就
/// 是設計給第三方網站直接用 iframe 嵌的，不是繞過什麼限制
/// （2026-09-30 使用者要求：點影片改預設內嵌播放，不用每次都跳出去
/// 開新分頁）。Flutter web 嵌 `dart:html` 元素要透過平台視圖
/// （`HtmlElementView`）——每個 videoId 各自註冊一個 view type，同一支
/// 影片重複開啟會重複註冊同一個 id，用 `_registered` 集合擋掉重複註冊
/// （Flutter 對同一個 view type 註冊兩次會丟例外）。
final _registered = <String>{};

Widget buildYtEmbeddedPlayer(String videoId) {
  final viewType = 'yt-embed-$videoId';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      return html.IFrameElement()
        // 2026-09-30 使用者最後決定：乾脆不要 autoplay 參數，一律停在
        // YouTube 預設的縮圖＋大播放鍵，使用者自己點才開始播——手機上
        // 反正這個組合（自動播放＋有聲音）本來就大機率被擋，結果還是要
        // 點一下；但拿掉 mute 那版在桌機瀏覽器有機會真的成功「無預警」
        // 自動出聲，使用者原話「避免哪時候不用點一下我被嚇到」，寧可
        // 每個平台都固定要點一下、行為一致可預期，也不要桌機偶爾嚇一跳。
        // 這個播放鍵是直接點在 YouTube 自己的內容上，任何瀏覽器都保證
        // 會有聲音，是最穩定的組合。
        ..src = 'https://www.youtube.com/embed/$videoId?rel=0'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow =
            'accelerometer; autoplay; clipboard-write; encrypted-media; '
            'gyroscope; picture-in-picture; web-share'
        ..allowFullscreen = true;
    });
  }
  return HtmlElementView(viewType: viewType);
}

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
        // 2026-09-30 使用者要求「要真的播放聲音」，明知手機（iOS Safari）
        // 大機率還是會被擋（自動播放＋有聲音這個組合，瀏覽器政策上幾乎
        // 一定二選一，見同一天跟使用者的討論），還是照要求拿掉 mute=1
        // 試試看——桌機瀏覽器（尤其是使用者對這個網域已經有播放過媒體
        // 紀錄的情況）有機會允許有聲自動播放，手機那邊會退回「停在縮圖，
        // 使用者自己點 YouTube 播放器中間的播放鍵」，不是程式壞掉，是
        // 瀏覽器直接擋掉沒有任何錯誤訊息（同上面舊版註解說明的機制）。
        ..src = 'https://www.youtube.com/embed/$videoId?autoplay=1&rel=0'
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

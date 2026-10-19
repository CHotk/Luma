// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// 音樂的 YouTube 播放器（2026-10-19）：整個 App 只有一個 iframe，換歌不重建，
/// 用 YouTube 官方內嵌播放器的 postMessage 介面（`enablejsapi=1`）控制——
/// `loadVideoById` 換下一首、`playVideo`／`pauseVideo`／`seekTo`，並收它回報
/// 的狀態（播完＝0 就自動接下一首）跟目前秒數。
///
/// 同一個 iframe 一直沿用：第一首要使用者自己點過播放（手機瀏覽器不讓網頁
/// 自己出聲），之後換歌是播放器自己換，不用每首再點。
class MusicYtBridge {
  MusicYtBridge(this.onEvent) {
    _sub = html.window.onMessage.listen(_onMessage);
  }

  final void Function(int? state, double? time, double? duration) onEvent;

  static const _viewType = 'music-yt';
  static var _registered = false;
  static html.IFrameElement? _frame;
  StreamSubscription<html.MessageEvent>? _sub;
  String? _current;
  Timer? _listenTimer;

  Widget view() {
    if (!_registered) {
      _registered = true;
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => _frame ??= _makeFrame(),
      );
    }
    return const HtmlElementView(viewType: _viewType);
  }

  html.IFrameElement _makeFrame() {
    final f = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow =
          'accelerometer; autoplay; clipboard-write; encrypted-media; '
          'gyroscope; picture-in-picture; web-share'
      ..allowFullscreen = true;
    f.onLoad.listen((_) => _startListening());
    if (_current != null) f.src = _src(_current!);
    return f;
  }

  String _src(String id) {
    final origin = Uri.encodeComponent(html.window.location.origin);
    return 'https://www.youtube.com/embed/$id'
        '?enablejsapi=1&autoplay=1&playsinline=1&rel=0&origin=$origin';
  }

  /// 跟播放器說「我要聽你的事件」（YouTube 收到後才會一直回報狀態）。
  /// iframe 剛載入時不一定接得到，前幾秒多送幾次。
  void _startListening() {
    _listenTimer?.cancel();
    var n = 0;
    _listenTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      _post({'event': 'listening', 'id': 'music', 'channel': 'widget'});
      if (++n >= 10) t.cancel();
    });
  }

  void _post(Map<String, Object?> msg) {
    _frame?.contentWindow?.postMessage(jsonEncode(msg), '*');
  }

  void _command(String func, [List<Object?> args = const []]) =>
      _post({'event': 'command', 'func': func, 'args': args});

  void _onMessage(html.MessageEvent e) {
    if (!e.origin.contains('youtube.com')) return;
    final raw = e.data;
    if (raw is! String) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    final info = m['info'];
    if (m['event'] == 'onStateChange' && info is num) {
      onEvent(info.toInt(), null, null);
    } else if (m['event'] == 'infoDelivery' && info is Map) {
      onEvent(
        (info['playerState'] as num?)?.toInt(),
        (info['currentTime'] as num?)?.toDouble(),
        (info['duration'] as num?)?.toDouble(),
      );
    }
  }

  /// 換成這部影片並開始播。第一次是設定 iframe 網址，之後叫播放器自己換。
  void load(String videoId) {
    final first = _current == null;
    _current = videoId;
    final f = _frame;
    if (f == null) return; // 還沒畫出來：畫出來時會用 _current
    if (first || f.src == null || f.src!.isEmpty) {
      f.src = _src(videoId);
    } else {
      _command('loadVideoById', [videoId]);
    }
  }

  void play() => _command('playVideo');
  void pause() => _command('pauseVideo');
  void seek(double seconds) => _command('seekTo', [seconds, true]);

  /// 停掉並清空（關掉播放器）。下一次 load 重新設定網址。
  void stop() {
    _command('stopVideo');
    _current = null;
    _frame?.src = 'about:blank';
  }

  void dispose() {
    _sub?.cancel();
    _listenTimer?.cancel();
  }
}

// 音樂播放器跟 YouTube 內嵌播放器溝通的那層，跟 `yt_embedded_player.dart`
// 同一套條件匯入理由：`dart:html`／`dart:ui_web` 在非網頁平台編譯不過。
export 'music_yt_bridge_stub.dart'
    if (dart.library.html) 'music_yt_bridge_web.dart';

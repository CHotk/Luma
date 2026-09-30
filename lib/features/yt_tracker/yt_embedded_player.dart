// 內嵌播放器，跟 `data/external_link.dart` 同一套條件匯入理由：
// `dart:html`／`dart:ui_web` 在非網頁平台編譯不過。
export 'yt_embedded_player_stub.dart'
    if (dart.library.html) 'yt_embedded_player_web.dart';

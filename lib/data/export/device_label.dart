// 這台裝置的名稱，寫進同步紀錄用（讓多台裝置的紀錄合在一起時分得出
// 是哪一台做的）。條件匯入理由同 `file_download.dart`。
export 'device_label_stub.dart' if (dart.library.html) 'device_label_web.dart';

/// 非網頁平台的預設實作。
///
/// 這個 App 目前只有網頁版真的在用，原生版還沒有存檔到裝置的功能，
/// 回傳 false 讓呼叫端知道下載沒有真的發生，可以退回複製剪貼簿。
bool saveTextFile(String filename, String content) => false;

bool saveBytesFile(String filename, List<int> bytes, String mimeType) => false;

/// 存一張圖片（手機叫系統分享、電腦下載）；非網頁平台還沒做。
Future<bool> shareOrSaveImage(String filename, List<int> png) async => false;

Future<bool> shareOrSaveFile(
  String filename,
  List<int> data,
  String mimeType,
) async => false;

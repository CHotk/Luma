// 檢查有沒有新版本（2026-10-20：手機「加入主畫面」的 Lume 常卡在舊版，同步來的
// 新格式資料讀不懂——歌手大頭貼就是這樣「沒同步」）。網頁版才有。
export 'update_check_stub.dart' if (dart.library.html) 'update_check_web.dart';

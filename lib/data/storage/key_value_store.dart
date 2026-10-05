import 'package:shared_preferences/shared_preferences.dart';

/// 儲存後端的唯一出入口。
///
/// v1 用 shared_preferences，之後要換成 drift（SQLite）時只改這個檔，
/// repository 以上的程式碼不用動。這就是為什麼要多包這一層。
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// 能把所有 key／value 一次列出來的儲存後端，給「本機儲存」檢視頁用
/// （2026-10-05）。另外開一個介面而不是加進 [KeyValueStore]：測試裡一堆
/// 假的 store 只實作讀寫刪，不用為了這一頁每個都補。
abstract interface class ListableKeyValueStore implements KeyValueStore {
  Future<Map<String, String>> readAll();
}

class SharedPrefsStore implements ListableKeyValueStore {
  SharedPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsStore> open() async =>
      SharedPrefsStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) async => _prefs.remove(key);

  @override
  Future<Map<String, String>> readAll() async => {
    for (final key in _prefs.getKeys())
      if (_prefs.get(key) case final String value) key: value,
  };
}

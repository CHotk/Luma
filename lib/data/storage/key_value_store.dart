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

class SharedPrefsStore implements KeyValueStore {
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
}

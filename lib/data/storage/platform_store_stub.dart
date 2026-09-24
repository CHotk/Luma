import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// 非網頁平台：沿用 shared_preferences。
Future<KeyValueStore> openPlatformStore() async =>
    SharedPrefsStore(await SharedPreferences.getInstance());

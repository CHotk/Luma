import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// 非網頁平台：沿用 shared_preferences。
Future<KeyValueStore> openPlatformStore() async =>
    SharedPrefsStore(await SharedPreferences.getInstance());

/// 瀏覽器的儲存配額估計，非網頁平台沒有這個概念，一律 null。
Future<({int? usage, int? quota})> estimateStorage() async =>
    (usage: null, quota: null);

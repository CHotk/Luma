import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/seed/app_defaults_loader.dart';
import 'data/storage/key_value_store.dart';

/// 開機流程做兩件事：把要非同步準備的儲存後端先開好，
/// 也把單字庫標籤排序這種讀資產檔的設定先讀好，再用 override 注進
/// provider。這樣畫面層就不必處理「還沒準備好」。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SharedPrefsStore.open();
  final tagOrder = await loadLibraryTagOrder();

  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        libraryTagOrderProvider.overrideWithValue(tagOrder),
      ],
      child: const LumeApp(),
    ),
  );
}

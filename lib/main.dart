import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/storage/key_value_store.dart';

/// 開機流程只做一件事：把要非同步準備的儲存後端先開好，
/// 再用 override 注進 provider。這樣畫面層就不必處理「還沒準備好」。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SharedPrefsStore.open();

  runApp(
    ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
      child: const LumeApp(),
    ),
  );
}

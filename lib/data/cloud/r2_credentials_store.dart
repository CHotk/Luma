import 'dart:convert';

import '../storage/key_value_store.dart';
import 'r2_client.dart';

/// R2 同步憑證存本機，**不像 YT API 金鑰那樣帶過期時間**——這把是用來
/// 讓裝置之間互相同步的，如果每天／每月就要求重貼一次，使用者根本
/// 不會想用這功能，跟 YT 金鑰「偶爾查一下資料才需要」的使用情境不
/// 一樣（2026-09-23 使用者要求同步憑證要能長期記住）。
class R2CredentialsStore {
  R2CredentialsStore(this._store);

  static const _key = 'r2_sync.credentials.v1';

  final KeyValueStore _store;

  Future<R2Credentials?> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    return R2Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(R2Credentials credentials) =>
      _store.write(_key, jsonEncode(credentials.toJson()));

  Future<void> clear() => _store.remove(_key);
}

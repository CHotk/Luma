import 'dart:convert';

import '../../domain/daily_limit.dart';
import '../../domain/rules_config.dart';
import '../storage/key_value_store.dart';

/// 設定與今日用量。
///
/// 這兩件事放一起是因為它們都很小、都常一起讀，
/// 而且都屬於「使用者可調的東西」。
class SettingsRepository {
  SettingsRepository(this._store);

  static const _rulesKey = 'rules.v1';
  static const _usageKey = 'usage.v1';

  final KeyValueStore _store;

  Future<RulesConfig> loadRules() async {
    final raw = await _store.read(_rulesKey);
    if (raw == null) return const RulesConfig();
    return RulesConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveRules(RulesConfig rules) async =>
      _store.write(_rulesKey, jsonEncode(rules.toJson()));

  /// 讀今日用量。跨日自動歸零，呼叫端不用自己判斷日期。
  Future<DailyUsage> loadUsage(DateTime now) async {
    final raw = await _store.read(_usageKey);
    if (raw == null) return DailyUsage(date: now);
    final stored = DailyUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return DailyLimit.rollOver(stored, now);
  }

  Future<void> saveUsage(DailyUsage usage) async =>
      _store.write(_usageKey, jsonEncode(usage.toJson()));
}

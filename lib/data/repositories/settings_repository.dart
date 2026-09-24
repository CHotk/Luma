import 'dart:convert';

import '../../domain/daily_limit.dart';
import '../../domain/rules_config.dart';
import '../seed/app_defaults_loader.dart';
import '../storage/key_value_store.dart';

/// 設定與今日用量。
///
/// 這兩件事放一起是因為它們都很小、都常一起讀，
/// 而且都屬於「使用者可調的東西」。
class SettingsRepository {
  SettingsRepository(this._store);

  static const _rulesKey = 'rules.v1';
  static const _usageKey = 'usage.v1';
  static const _rulesUpdatedKey = 'rules.updated_at.v1';
  static const _lastTrackKey = 'track.last';

  final KeyValueStore _store;

  Future<RulesConfig> loadRules() async {
    final raw = await _store.read(_rulesKey);
    // 使用者存過設定就用那份；沒存過（全新使用者）才讀資產檔的預設值。
    if (raw == null) return loadDefaultRulesConfig();
    return RulesConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// 存設定。順便記下「這份設定最後改的時間」，多裝置同步用它比新舊
  /// （2026-09-24 設定也加入同步：整份取最後改的那台，不是逐欄位合併）。
  Future<void> saveRules(RulesConfig rules) async {
    await _store.write(_rulesKey, jsonEncode(rules.toJson()));
    await _store.write(_rulesUpdatedKey, DateTime.now().toIso8601String());
  }

  /// 給同步用：本機設定＋最後改的時間。從沒改過（一直用預設值）就是
  /// null，代表「沒有東西可以上傳」。
  Future<({RulesConfig rules, DateTime updatedAt})?> rulesForUpload() async {
    final raw = await _store.read(_rulesKey);
    final stamp = await _store.read(_rulesUpdatedKey);
    if (raw == null) return null;
    return (
      rules: RulesConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      updatedAt:
          DateTime.tryParse(stamp ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 雲端那份比本機新才套用，回傳有沒有套用。
  Future<bool> applyFromCloud(RulesConfig rules, DateTime updatedAt) async {
    final local = await rulesForUpload();
    if (local != null && !updatedAt.isAfter(local.updatedAt)) return false;
    await _store.write(_rulesKey, jsonEncode(rules.toJson()));
    await _store.write(_rulesUpdatedKey, updatedAt.toIso8601String());
    return true;
  }

  /// 讀今日用量。跨日自動歸零，呼叫端不用自己判斷日期。
  Future<DailyUsage> loadUsage(DateTime now) async {
    final raw = await _store.read(_usageKey);
    if (raw == null) return DailyUsage(date: now);
    final stored = DailyUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return DailyLimit.rollOver(stored, now);
  }

  Future<void> saveUsage(DailyUsage usage) async =>
      _store.write(_usageKey, jsonEncode(usage.toJson()));

  /// 上次選的語言軌道（存的是 [LearningTrack.name]，例如 'en'／'ja'）。
  /// 開機畫面看這個決定要跳去哪個首頁，不然每次啟動都固定跳英文，
  /// 常用日文軌道的人每次都要手動切一次（2026-09-18 使用者要求）。
  Future<String?> loadLastTrack() => _store.read(_lastTrackKey);

  Future<void> saveLastTrack(String track) =>
      _store.write(_lastTrackKey, track);
}

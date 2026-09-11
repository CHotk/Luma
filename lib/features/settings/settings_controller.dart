import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/rules_config.dart';

/// 設定頁的狀態。
///
/// 這裡是全 App 唯一會改 [RulesConfig] 的地方。
/// 改完立刻寫進儲存，不做「按確定才生效」那一套，
/// 這種小設定多一步確認只是多一步麻煩。
class SettingsController extends AsyncNotifier<RulesConfig> {
  @override
  Future<RulesConfig> build() =>
      ref.read(settingsRepositoryProvider).loadRules();

  /// 套用新的設定。名字不叫 update，那個名稱被 AsyncNotifier 用掉了。
  Future<void> apply(RulesConfig next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).saveRules(next);
    // 門檻改了，單字的狀態判定會跟著變，讓單字庫重算。
    ref.read(wordRepositoryProvider).invalidate();
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, RulesConfig>(
      SettingsController.new,
    );

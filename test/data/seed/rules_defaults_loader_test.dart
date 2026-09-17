import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/seed/rules_defaults_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rules_defaults.yaml 真的被讀進來，不是掉進 fallback', () async {
    final rules = await loadDefaultRulesConfig();
    expect(rules.confirmRight, 4);
    expect(rules.recoveryRatio, 5);
    expect(rules.roundSize, 10);
  });
}

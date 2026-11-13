import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/repositories/yt_api_key_store.dart';

import '../support/poke.dart';

/// YT 金鑰預設存三個月（2026-11-13 使用者要求，原本一週）：剛存的讀得到；舊格式
/// （只有 expiresAt）照當初存的時間重算、跟著延長；超過 90 天自動清掉；清除。
void main() {
  const key = 'yt_tracker.api_key.v1';

  test('效期是 90 天', () {
    expect(YtApiKeyStore.validFor, const Duration(days: 90));
  });

  test('剛存的讀得到，清掉就沒有', () async {
    final s = MemoryStore();
    final store = YtApiKeyStore(s);
    expect(await store.load(), isNull);
    await store.save('KEY');
    expect(await store.load(), 'KEY');
    final json = jsonDecode(s.data[key]!) as Map<String, dynamic>;
    final saved = DateTime.parse(json['savedAt'] as String);
    final expires = DateTime.parse(json['expiresAt'] as String);
    expect(expires.difference(saved), const Duration(days: 90));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('舊格式：一週前到期的（30 天前存的）照新效期還有效', () async {
    final s = MemoryStore();
    // 30 天前存、當時一週後到期 → 舊規則早就過期，新規則（90 天）還有效。
    final oldExpires = DateTime.now().subtract(const Duration(days: 23));
    s.data[key] = jsonEncode({
      'key': 'OLD',
      'expiresAt': oldExpires.toIso8601String(),
    });
    expect(await YtApiKeyStore(s).load(), 'OLD');
  });

  test('超過 90 天：自動清掉', () async {
    final s = MemoryStore();
    s.data[key] = jsonEncode({
      'key': 'K',
      'savedAt': DateTime.now()
          .subtract(const Duration(days: 90, minutes: 1))
          .toIso8601String(),
    });
    expect(await YtApiKeyStore(s).load(), isNull);
    expect(s.data.containsKey(key), isFalse);
    // 舊格式、存了 100 天的也清掉。
    s.data[key] = jsonEncode({
      'key': 'K',
      'expiresAt': DateTime.now()
          .subtract(const Duration(days: 93))
          .toIso8601String(),
    });
    expect(await YtApiKeyStore(s).load(), isNull);
  });

  test('89 天還有效', () async {
    final s = MemoryStore();
    s.data[key] = jsonEncode({
      'key': 'K',
      'savedAt': DateTime.now()
          .subtract(const Duration(days: 89))
          .toIso8601String(),
    });
    expect(await YtApiKeyStore(s).load(), 'K');
  });
}

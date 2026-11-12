import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume/app/providers.dart';
import 'package:lume/data/repositories/yt_tracker_repository.dart';
import 'package:lume/domain/models/yt_tracker.dart';
import 'package:lume/features/yt_tracker/yt_tracker_home_page.dart';
import '../../support/poke.dart';
import '../../support/yt_fake.dart';
void main() {
  testWidgets('dbg', (tester) async {
    final store = MemoryStore();
    await seedYt(tester, store);
    await tester.runAsync(() => YtTrackerRepository(store).addCategory(const YtCategory(id: 'c3', name: '幣圈', colorValue: 0xFFFFC857)));
    final yt = FakeYoutube();
    await http.runWithClient(() => pumpPage(tester, store, () => const YtTrackerHomePage(), size: const Size(390, 860), overrides: [ytApiKeyProvider.overrideWith((_) => 'KEY')]), yt.client);
    await settle(tester, 6);
    debugPrint('TEXTS ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
    debugPrint('EXC ${tester.takeException()}');
  });
}

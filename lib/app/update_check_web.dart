import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// 這一版的部署編號（部署時用 --dart-define=BUILD_ID=... 帶進來；本機開發是空的）。
const buildId = String.fromEnvironment('BUILD_ID');

/// 線上的 build_id.txt（每次部署寫的）跟自己不一樣＝有新版本。
Future<bool> hasNewerBuild() async {
  if (buildId.isEmpty) return false;
  try {
    final url = Uri.base.resolve(
      'build_id.txt?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final r = await http.get(url).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return false;
    final latest = r.body.trim();
    return latest.isNotEmpty && latest != buildId;
  } catch (_) {
    return false;
  }
}

/// 更新到最新版：清掉離線快取程式（service worker）跟它存的檔案，再重新載入。
Future<void> _clearAndReload() async {
  try {
    final regs = await web.window.navigator.serviceWorker.getRegistrations().toDart;
    for (final r in regs.toDart) {
      await r.unregister().toDart;
    }
  } catch (_) {}
  try {
    final keys = await web.window.caches.keys().toDart;
    for (final k in keys.toDart) {
      await web.window.caches.delete(k.toDart).toDart;
    }
  } catch (_) {}
  web.window.location.reload();
}

void reloadToLatest() => _clearAndReload();

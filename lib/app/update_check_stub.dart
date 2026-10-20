/// 這一版的部署編號（部署時用 --dart-define=BUILD_ID=... 帶進來；本機開發是空的）。
const buildId = String.fromEnvironment('BUILD_ID');

/// 非網頁平台：沒有線上版本可比。
Future<bool> hasNewerBuild() async => false;

void reloadToLatest() {}

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/shared/small_asset.dart';

void main() {
  test('有縮小版的資料夾，換成同資料夾底下的 small/', () {
    expect(
      smallAssetFor('assets/images/yt_tracker/crypto.png'),
      'assets/images/yt_tracker/small/crypto.png',
    );
    expect(
      smallAssetFor('assets/images/nav_icons/diary.png'),
      'assets/images/nav_icons/small/diary.png',
    );
  });

  test('已經是 small/、子資料夾、其他資料夾、網址都原樣傳回', () {
    for (final path in [
      'assets/images/yt_tracker/small/crypto.png',
      'assets/images/yt_tracker/備用/old.png',
      'assets/images/app_logo/logo02.png',
      'https://example.com/a.png',
    ]) {
      expect(smallAssetFor(path), path);
    }
  });
}

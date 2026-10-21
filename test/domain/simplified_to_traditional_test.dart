import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/simplified_to_traditional.dart';
import 'package:lume/features/music/music_actions.dart';

void main() {
  test('簡體標題轉繁體', () {
    expect(toTraditional('周杰伦《晴天》官方MV 后来'), '周杰倫《晴天》官方MV 後來');
    expect(toTraditional('已經是繁體'), '已經是繁體');
    expect(toTraditional('天后于文文'), '天后于文文');
  });

  test('猜歌名時簡體先轉繁體', () {
    expect(MusicGuess.guessTitle(toTraditional('【后来】刘若英 官方MV'), const []), '後來');
  });
}

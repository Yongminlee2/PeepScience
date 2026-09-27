import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/piyak_game.dart';

import '../sim/helpers.dart';

void main() {
  // 힌트는 정답 부품을 하나씩 늘려 보여 주고, 다 보여 주면 더 늘지 않는다.
  // (반투명 부품이 실제로 그려지는지는 실기기에서 확인한다 - 테스트 환경은
  // 배경 그림 해독을 기다리지 않아 장면이 뜨지 않는다.)
  test('힌트는 정답 부품 수만큼만 늘어난다', () {
    final s = stage(
      '{"type":"basket","x":8,"y":6,"angle":0},'
          '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
      '{"type":"plank","count":2}',
      '{"type":"plank","x":4,"y":4,"angle":0},'
          '{"type":"plank","x":11,"y":4,"angle":0}',
    );
    final game = PiyakGame(s);
    expect(game.hintsShown, 0);
    expect(game.hasMoreHints, isTrue);
    game.revealHint();
    expect(game.hintsShown, 1);
    game.revealHint();
    expect(game.hintsShown, 2);
    expect(game.hasMoreHints, isFalse);
    game.revealHint();
    expect(game.hintsShown, 2);
  });
}

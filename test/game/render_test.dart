import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/piyak_game.dart';

import '../sim/helpers.dart';

void main() {
  testWidgets('게임이 뜨고 run 모드에서 공이 움직인다', (t) async {
    final s = stage(
      '{"type":"rubber_ball","x":5,"y":1,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
    );
    final game = PiyakGame(s);
    await t.pumpWidget(GameWidget(game: game));
    await t.pump(); // onLoad
    game.startRun();
    final before = game.ballY(); // 테스트용 헬퍼: 첫 공 y
    game.update(0.5);
    expect(game.ballY(), greaterThan(before)); // 낙하 (y-down)
  });
}

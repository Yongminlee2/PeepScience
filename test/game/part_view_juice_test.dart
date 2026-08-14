import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/part_view.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';

import '../sim/helpers.dart';

void main() {
  // 순수 단위 테스트 - PartView는 body가 없어도(에딧 모드 생성자) 그냥
  // Dart 객체라 마운트/펌프 없이 바로 생성해 게터를 읽을 수 있다.
  test('공 도형은 회전이 보이는 중심 이탈 마커를 갖고, 공이 아닌 도형은 마커가 없다', () {
    final ball = PartView(part: PartType.rubberBall, posM: Vector2.zero(), angleRad: 0);
    final offset = ball.rollMarkerOffset;
    expect(offset, isNotNull);
    expect(offset!.dx, greaterThan(0)); // 중심에서 벗어나 있어야 회전이 눈에 보인다
    expect(offset.dy, 0);

    final metalBall =
        PartView(part: PartType.metalBall, posM: Vector2.zero(), angleRad: 0);
    expect(metalBall.rollMarkerOffset, isNotNull);

    final plank = PartView(part: PartType.plank, posM: Vector2.zero(), angleRad: 0);
    expect(plank.rollMarkerOffset, isNull);
  });

  testWidgets(
      'run 모드에서 공이 발판에 충돌하면 스쿼시가 튀었다가 정확히 스케일 1.0으로 돌아오고, 먼지 퍼프도 수명 후 사라진다',
      (t) async {
    // 발판(y=8, 상단은 y=8-0.2=7.8) 위 1.8m 지점에서 공을 자유낙하시켜
    // 착지 순간 sqrt(2*10*1.8)≈6m/s의 충돌 속도를 만든다 - 스쿼시/먼지
    // 임계값(3m/s)을 넉넉히 넘는다. 공은 preset에 직접 놓아 run 시작과
    // 동시에 존재하게 한다(solution은 StageData 검증상 비어 있을 수
    // 없어 더미로 채운다 - 실제로 다시 놓이진 않는다).
    final s = stage(
      '{"type":"platform","x":8,"y":8,"angle":0,"w":4},'
      '{"type":"rubber_ball","x":8,"y":6,"angle":0}',
      '',
      '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
    );
    final game = PiyakGame(s);
    await t.pumpWidget(GameWidget(game: game));
    // world.children이 실제로 채워지려면 진짜 스프라이트 디코드가 먼저
    // 끝나야 한다: stage.world=1(test/sim/helpers.dart의 stage() 헬퍼가
    // 고정)이라 _BackgroundView가 이미 번들된 bg/world1.png를, 이 공
    // (rubber_ball)도 이미 번들된 parts/rubber_ball.png를 진짜로
    // Sprite.load한다 - dart:ui 이미지 디코드는 진짜 비동기 콜백이라
    // FakeAsync 안에서는 t.pump()를 아무리 반복해도 끝나지 않는다
    // (sprite_fallback_test.dart/goal_pulse_test.dart의 동일 comment 참고,
    // 직접 확인: runAsync 없이 20회 pump해도 world.children이 계속
    // 비어 있었다). runAsync로 진짜 이벤트 루프를 한 번 돌려야 한다.
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }
    game.startRun();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }

    PartView ball() => game.world.children
        .whereType<PartView>()
        .firstWhere((v) => v.part == PartType.rubberBall);

    // goal_pulse_test.dart의 _pumpSeconds와 동일 관례: t.pump(duration)이
    // GameWidget의 티커를 거쳐 game.update(dt)를 호출하므로 물리 스텝뿐
    // 아니라 컴포넌트 마운트/트리도 함께 정상 처리된다 - game.update()를
    // 직접 반복 호출하면(run_flow_test.dart처럼 raw 시뮬레이션 상태만 읽는
    // 경우엔 괜찮지만) 이 테스트처럼 world.children을 읽을 때는 새
    // PartView가 안 잡히는 것을 실제로 확인했다. 100ms * 60 = 6초 -
    // 충돌·스쿼시·먼지 관측과, 반발 감쇠 후 완전히 정지하는 것까지 넉넉히
    // 담는다(정확히 몇 번 튀는지 물리로 예측하지 않고 여유를 둔다).
    var sawSquash = false;
    var sawDust = false;
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (ball().scale.x != 1.0 || ball().scale.y != 1.0) sawSquash = true;
      if (game.world.children.whereType<ParticleSystemComponent>().isNotEmpty) {
        sawDust = true;
      }
    }
    expect(sawSquash, isTrue, reason: '충돌 스쿼시가 한 번도 관측되지 않음');
    expect(sawDust, isTrue, reason: '먼지 퍼프가 한 번도 관측되지 않음');
    expect(ball().scale.x, 1.0);
    expect(ball().scale.y, 1.0);
    expect(game.world.children.whereType<ParticleSystemComponent>(), isEmpty);
  });
}

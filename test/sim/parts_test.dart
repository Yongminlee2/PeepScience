import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/sim_world.dart';

import 'helpers.dart';

void main() {
  test('트램펄린: 고무공이 낙하 높이의 절반 이상 되튄다', () {
    final s = stage(
      '{"type":"trampoline","x":5,"y":7,"angle":0},'
      '{"type":"rubber_ball","x":5,"y":1,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
    );
    final w = SimWorld(s, const []);
    final ball = w.world.bodies
        .firstWhere((b) => (b.userData as PartTag?)?.part == PartType.rubberBall);
    var minY = ball.position.y;
    for (var i = 0; i < 400; i++) {
      w.step();
      if (ball.position.y < minY) minY = ball.position.y;
    }
    // 낙하 시작 y=1, 트램펄린 표면 y~6.85 -> 낙하 높이 절반 이상 되튀면 y<4.5.
    expect(minY, lessThan(4.5));
  });

  test('풍선은 떠오르고 압정에 닿으면 사라진다', () {
    final s = stage(
      '{"type":"balloon","x":5,"y":6,"angle":0},'
      '{"type":"tack","x":5,"y":2,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
    );
    final w = SimWorld(s, const []);
    final balloon = w.world.bodies
        .firstWhere((b) => (b.userData as PartTag?)?.part == PartType.balloon);
    var lastY = balloon.position.y;
    var popped = false;
    for (var i = 0; i < 600; i++) {
      w.step();
      if (!w.world.bodies.contains(balloon)) {
        popped = true;
        break;
      }
      final y = balloon.position.y;
      // y-down: 위로 떠오르는 동안 y가 단조 감소해야 한다(부동소수 오차만 허용).
      expect(y, lessThanOrEqualTo(lastY + 1e-6));
      lastY = y;
    }
    expect(popped, isTrue, reason: '압정을 지나쳐도 사라지지 않았다');
    // 압정(y=2, r=0.12)과 풍선(r=0.4)의 접촉 반경은 y~2.52 부근이다. 여기서
    // 사라져야 진짜 "압정에 닿아 펑" 이다 - 화면 밖 정리(y<-2)로 사라진 것이면
    // lastY가 이 범위를 한참 벗어난다.
    expect(lastY, greaterThan(1.5));
    expect(lastY, lessThan(3.2));
  });

  test('시소: 무거운 쇠공이 떨어지면 반대편 고무공이 발사된다', () {
    final s = stage(
      '{"type":"seesaw","x":8,"y":6,"angle":0},'
      '{"type":"rubber_ball","x":9.3,"y":5.6,"angle":0},'
      '{"type":"metal_ball","x":6.9,"y":5.0,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
    );
    final w = SimWorld(s, const []);
    final rubber = w.world.bodies
        .firstWhere((b) => (b.userData as PartTag?)?.part == PartType.rubberBall);
    final metal = w.world.bodies
        .firstWhere((b) => (b.userData as PartTag?)?.part == PartType.metalBall);
    // 낙하 시작점(5.0)에서 이미 어느 정도 가속된 상태로 만들어, 고무공이 얹힌
    // 반대편 끝이 자기 무게만으로 기울어 미끄러져 내리기 전에 충격이 도착하게 한다.
    metal.linearVelocity = Vector2(0, 6);
    var minVy = rubber.linearVelocity.y;
    for (var i = 0; i < 300; i++) {
      w.step();
      if (rubber.linearVelocity.y < minVy) minVy = rubber.linearVelocity.y;
    }
    // y-down이라 위로 튀어오르는 속도는 음수. -3보다 작아야(더 큰 속도) 발사로 인정.
    expect(minVy, lessThan(-3));
  });

  test('도미노 3개 연쇄', () {
    final s = stage(
      '{"type":"platform","x":8,"y":8,"angle":0,"w":10},'
      '{"type":"domino","x":6.0,"y":7.35,"angle":0},'
      '{"type":"domino","x":6.6,"y":7.35,"angle":0},'
      '{"type":"domino","x":7.2,"y":7.35,"angle":0},'
      '{"type":"rubber_ball","x":4.5,"y":7.5,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
    );
    final w = SimWorld(s, const []);
    final dominoes = w.world.bodies
        .where((b) => (b.userData as PartTag?)?.part == PartType.domino)
        .toList();
    expect(dominoes.length, 3);
    final ball = w.world.bodies
        .firstWhere((b) => (b.userData as PartTag?)?.part == PartType.rubberBall);
    ball.linearVelocity = Vector2(5, 0); // 공 굴리기
    for (var i = 0; i < 400; i++) {
      w.step();
    }
    for (final d in dominoes) {
      expect(d.angle.abs(), greaterThan(0.7));
    }
  });
}

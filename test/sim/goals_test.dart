import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/sim_world.dart';
import 'package:piyak_science/sim/stage_data.dart';

import 'helpers.dart';

void main() {
  test('버튼 목표: 공이 버튼 위로 떨어지면 클리어', () {
    final s = stage(
      '{"type":"button","x":5,"y":7,"angle":0},'
          '{"type":"rubber_ball","x":5,"y":1,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
      goal: 'press_button',
    );
    final w = SimWorld(s, const []);
    for (var i = 0; i < 300 && !w.cleared; i++) {
      w.step();
    }
    expect(w.cleared, isTrue);
  });

  test('풍선 목표: 프리셋 풍선을 모두 압정에 터뜨리면 클리어', () {
    final s = stage(
      '{"type":"balloon","x":4,"y":6,"angle":0},'
          '{"type":"balloon","x":6,"y":6,"angle":0},'
          '{"type":"tack","x":4,"y":2,"angle":0},'
          '{"type":"tack","x":6,"y":2,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
      goal: 'pop_balloons',
    );
    final w = SimWorld(s, const []);
    for (var i = 0; i < 600 && !w.cleared; i++) {
      w.step();
    }
    expect(w.cleared, isTrue);
    expect(w.poppedPresetCount, 2);
  });

  test('풍선 목표: 플레이어가 배치한 풍선은 카운트되지 않는다', () {
    final s = stage(
      // 프리셋 풍선 근처에는 압정이 없다 - 이 풍선은 끝까지 터지지 않는다.
      '{"type":"balloon","x":4,"y":6,"angle":0},'
          '{"type":"tack","x":8,"y":2,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
      goal: 'pop_balloons',
    );
    // 플레이어가 배치한 풍선만 압정에 닿아 터진다.
    final placements = [
      Placement(type: PartType.balloon, x: 8, y: 6, angleDeg: 0),
    ];
    final w = SimWorld(s, placements);
    for (var i = 0; i < 600; i++) {
      w.step();
    }
    expect(w.poppedPresetCount, 0, reason: '플레이어 풍선은 프리셋 카운트에 들어가면 안 된다');
    expect(w.cleared, isFalse);
  });

  test('도미노 목표: 프리셋 도미노가 전부 쓰러지면 클리어', () {
    final s = stage(
      '{"type":"domino","x":6,"y":7.35,"angle":0},'
          '{"type":"domino","x":7,"y":7.35,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
      goal: 'topple_dominoes',
    );
    final w = SimWorld(s, const []);
    // 물리 연쇄가 아니라 목표 판정 자체를 검증하는 테스트이므로, 이미 쓰러진
    // 상태를 직접 만들어 판정 로직만 확인한다(연쇄 반응은 parts_test.dart 담당).
    for (final b in w.world.bodies) {
      if ((b.userData as PartTag?)?.part == PartType.domino) {
        b.setTransform(b.position, 1.2); // 0.7rad 임계값을 넉넉히 넘긴 값
      }
    }
    w.step();
    expect(w.cleared, isTrue);
  });

  test('도미노 목표: 하나라도 서 있으면 미달', () {
    final s = stage(
      '{"type":"domino","x":6,"y":7.35,"angle":0},'
          '{"type":"domino","x":7,"y":7.35,"angle":0}',
      '',
      '{"type":"plank","x":0,"y":0,"angle":0}',
      goal: 'topple_dominoes',
    );
    final w = SimWorld(s, const []);
    final dominoes = w.world.bodies
        .where((b) => (b.userData as PartTag?)?.part == PartType.domino)
        .toList();
    expect(dominoes.length, 2);
    dominoes[0].setTransform(dominoes[0].position, 1.2); // 하나만 쓰러뜨림
    // dominoes[1]은 angle 0으로 그대로 서 있다.
    w.step();
    expect(w.cleared, isFalse);
  });

  test('수집 별은 공 접촉 시 사라지고 클리어와 별도로 기록된다', () {
    final s = StageData(
      id: 'star_test',
      world: 1,
      index: 1,
      goal: GoalSpec(type: GoalType.ballInBasket),
      preset: [
        PresetObject(type: 'rubber_ball', x: 5, y: 1, angleDeg: 0),
        PresetObject(type: 'basket', x: 5, y: 7, angleDeg: 0),
      ],
      tray: [TrayEntry(type: PartType.plank, count: 1)],
      solution: [Placement(type: PartType.plank, x: 1, y: 1, angleDeg: 0)],
      challenge: const ChallengeSpec(
        partLimit: 1,
        collectibleStar: CollectibleStarSpec(x: 5, y: 4),
      ),
    );
    final w = SimWorld(s, const []);
    for (var i = 0; i < 600 && !w.cleared; i++) {
      w.step();
    }
    expect(w.starCollected, isTrue);
    expect(w.cleared, isTrue);
  });
}

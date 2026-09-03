import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/sim_world.dart';
import 'package:piyak_science/sim/stage_data.dart';

StageData _load(String id) => StageData.fromJson(
  jsonDecode(File('assets/stages/$id.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  test('대표 연쇄 반응 스테이지에 기능 표식이 있다', () {
    expect(_load('w1_s05').feature, StageFeature.chainReaction);
    expect(_load('w3_s10').feature, StageFeature.chainReaction);
    expect(_load('w4_s10').feature, StageFeature.chainReaction);
  });

  test('공 비교 실험은 쇠공 예측과 한 부품 도전을 사용한다', () {
    final stage = _load('w2_s05');
    expect(stage.prediction!.answer, PartType.metalBall);
    expect(stage.challenge!.partLimit, 1);
  });

  test('후반 50판은 목표 물체를 고정하고 긴 장치·여분 부품 도전을 제공한다', () {
    final masteryIds = stageOrder.where(
      (id) => int.parse(id.substring(id.length - 2)) >= 11,
    );
    expect(masteryIds.length, 50);
    var stagesWithThreeParts = 0;
    var stagesWithTwoToolTypes = 0;
    final playerTools = <PartType>{};
    for (final id in masteryIds) {
      final stage = _load(id);
      final trayCount = stage.tray.fold(0, (sum, entry) => sum + entry.count);
      final solutionTypes = stage.solution.map((part) => part.type).toSet();
      expect(stage.challenge, isNotNull, reason: id);
      expect(stage.solution.length, greaterThanOrEqualTo(2), reason: id);
      expect(stage.challenge!.partLimit, stage.solution.length, reason: id);
      expect(trayCount, greaterThan(stage.solution.length), reason: id);
      for (final part in stage.solution) {
        if (!Catalog.of(part.type).rotatable) {
          expect(part.angleDeg, 0, reason: '$id ${jsonIdOf(part.type)}');
        }
      }
      if (stage.solution.length >= 3) stagesWithThreeParts++;
      if (solutionTypes.length >= 2) stagesWithTwoToolTypes++;
      playerTools.addAll(solutionTypes);
    }

    expect(stagesWithThreeParts, greaterThanOrEqualTo(47));
    expect(stagesWithTwoToolTypes, greaterThanOrEqualTo(36));
    expect(
      playerTools,
      containsAll(const {
        PartType.plank,
        PartType.seesaw,
        PartType.motorGear,
        PartType.gear,
        PartType.paddleGear,
        PartType.fan,
        PartType.trampoline,
      }),
    );
  });

  test('후반 50판은 공·압정을 목표 바로 위에 놓는 직행 해법을 지급하지 않는다', () {
    final masteryIds = stageOrder.where(
      (id) => int.parse(id.substring(id.length - 2)) >= 11,
    );
    // 무게·재질 함정 판은 예외: 트레이에 정답 재질과 오답 재질 공을 나란히
    // 지급하는 것(쇠공↔고무공 선택)이 퍼즐의 핵심이다. 목표 지점이 지붕·통로
    // 안쪽에 있어 공을 위에서 떨어뜨리는 직행 해법은 성립하지 않음을 전 지점
    // 낙하 스윕 시뮬레이션(양 재질 각 500여 지점, 클리어 0건)으로 확인했다.
    // w5_s16(바운스 계측 대들보 갤러리) metal/rubber 0/583,
    // w5_s17(맞바람 터널 관문) metal/rubber 0/596.
    // w2_s12(천장 밑 바구니)는 바구니를 천장 바로 아래로 올려, 바구니 위쪽에
    // 공을 놓을 수 있는 자리 자체가 없어졌다: 0.2m 격자 전 지점 스윕에서
    // metal 0/2359 · rubber 0/2359 · 널빤지(16각) 0/35122.
    // w2_s15(경사로 밑 버튼)는 버튼 선반을 경사로 바로 아래까지 올려 버튼 위쪽
    // 빈 방을 없앴다. 출하 감사기 격자 0건. 0.05m 격자 전 지점 스윕에서는 선반
    // 턱 바로 위 0.15×0.10m 띠(양 재질 각 8/35126)만 남는데, 정답 공이 그 턱을
    // 굴러 넘어 버튼을 누르는 자리라 배치 규칙(반지름+0.02m)으로는 더 못 막는다.
    const materialTrapIds = {'w2_s12', 'w2_s15', 'w5_s16', 'w5_s17'};
    for (final id in masteryIds) {
      if (materialTrapIds.contains(id)) continue;
      final stage = _load(id);
      final trayTypes = stage.tray.map((entry) => entry.type).toSet();
      final forbidden = switch (stage.goal.type) {
        GoalType.ballInBasket => const {
          PartType.rubberBall,
          PartType.metalBall,
        },
        GoalType.pressButton => const {
          PartType.rubberBall,
          PartType.metalBall,
          PartType.balloon,
          PartType.domino,
        },
        GoalType.popBalloons => const {PartType.tack},
        GoalType.toppleDominoes => const {
          PartType.rubberBall,
          PartType.metalBall,
        },
      };
      expect(trayTypes.intersection(forbidden), isEmpty, reason: id);
    }
  });

  test('후반 50판은 정답 부품을 하나라도 빼면 클리어되지 않는다', () {
    final masteryIds = stageOrder.where(
      (id) => int.parse(id.substring(id.length - 2)) >= 11,
    );
    for (final id in masteryIds) {
      final stage = _load(id);
      for (var i = 0; i < stage.solution.length; i++) {
        final reduced = [...stage.solution]..removeAt(i);
        expect(
          SimWorld.verify(stage, reduced),
          isFalse,
          reason: '$id solution[$i]=${jsonIdOf(stage.solution[i].type)}',
        );
      }
    }
  });

  for (final id in ['w1_s10', 'w1_s20', 'w3_s10', 'w3_s20', 'w5_s10', 'w5_s20']) {
    test('$id 정답 경로에서 수집 별을 실제로 얻을 수 있다', () {
      final stage = _load(id);
      final sim = SimWorld(stage, stage.solution);
      for (var i = 0; i < 1800 && !sim.cleared; i++) {
        sim.step();
      }
      expect(sim.cleared, isTrue);
      expect(sim.starCollected, isTrue);
    });
  }
}

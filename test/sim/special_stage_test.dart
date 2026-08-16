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

  test('후반 40판은 목표 물체를 고정하고 긴 장치·여분 부품 도전을 제공한다', () {
    final masteryIds = stageOrder.where(
      (id) => int.parse(id.substring(id.length - 2)) >= 11,
    );
    expect(masteryIds.length, 40);
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

    expect(stagesWithThreeParts, greaterThanOrEqualTo(37));
    expect(stagesWithTwoToolTypes, greaterThanOrEqualTo(26));
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

  test('후반 40판은 공·압정을 목표 바로 위에 놓는 직행 해법을 지급하지 않는다', () {
    final masteryIds = stageOrder.where(
      (id) => int.parse(id.substring(id.length - 2)) >= 11,
    );
    for (final id in masteryIds) {
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

  test('후반 40판은 정답 부품을 하나라도 빼면 클리어되지 않는다', () {
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

  for (final id in ['w1_s10', 'w1_s20', 'w3_s10', 'w3_s20']) {
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

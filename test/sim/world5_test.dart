import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/sim_world.dart';
import 'package:piyak_science/sim/stage_data.dart';

// 월드5(하드 챕터)는 s01부터 숙련판 규약을 따르는 최종 난이도 월드다.
// special_stage_test.dart의 "후반 40판" 테스트들이 index >= 11만 걸러내기
// 때문에 w5_s01~s10은 그 그물에 안 걸린다 - 같은 불변식을 여기서 강제한다.

StageData _load(String id) => StageData.fromJson(
  jsonDecode(File('assets/stages/$id.json').readAsStringSync())
      as Map<String, dynamic>,
);

Iterable<String> get _world5Ids => stageOrder.where((id) => id.startsWith('w5_'));

void main() {
  test('월드5 전판이 숙련판 패턴(부품 3~5개, 제한=정답수, 여분 1)을 따른다', () {
    for (final id in _world5Ids) {
      final stage = _load(id);
      final trayCount = stage.tray.fold(0, (sum, e) => sum + e.count);
      expect(stage.solution.length, inInclusiveRange(3, 5), reason: id);
      expect(stage.challenge, isNotNull, reason: id);
      expect(stage.challenge!.partLimit, stage.solution.length, reason: id);
      expect(trayCount, stage.solution.length + 1, reason: id);
      for (final part in stage.solution) {
        if (!Catalog.of(part.type).rotatable) {
          expect(part.angleDeg, 0, reason: '$id ${jsonIdOf(part.type)}');
        }
      }
      // 하드 챕터의 핵심: 단일 부품 반복이 아니라 조합 - 정답에 서로 다른
      // 부품 타입이 최소 2종.
      expect(
        stage.solution.map((p) => p.type).toSet().length,
        greaterThanOrEqualTo(2),
        reason: id,
      );
    }
  });

  test('월드5는 네 가지 목표 타입을 모두 사용한다', () {
    final goals = _world5Ids.map((id) => _load(id).goal.type).toSet();
    expect(
      goals,
      containsAll(const {
        GoalType.ballInBasket,
        GoalType.pressButton,
        GoalType.popBalloons,
        GoalType.toppleDominoes,
      }),
    );
  });

  test('월드5는 정답 부품을 하나라도 빼면 클리어되지 않는다', () {
    for (final id in _world5Ids) {
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

  test('월드5는 목표 재료를 직행 투하할 수 있게 지급하지 않는다', () {
    // 재질 함정 판은 예외: 트레이에 정답 재질과 오답 재질 공을 나란히 주는
    // 선택이 퍼즐의 본체다(w2_s12/s15와 같은 규약). 네 판 모두 전 지점 단독
    // 낙하 스윕(0.4m 격자, 배치 규칙 통과 지점만)으로 직행 클리어 0건을
    // 시뮬레이션으로 확인했다: w5_s04 metal 0/554·rubber 0/554,
    // w5_s08 rubber 0/588·metal 0/588, w5_s16 metal 0/581·rubber 0/581,
    // w5_s17 metal 0/614·rubber 0/614.
    const materialTrapIds = {'w5_s04', 'w5_s08', 'w5_s16', 'w5_s17'};
    for (final id in _world5Ids) {
      if (materialTrapIds.contains(id)) continue;
      final stage = _load(id);
      final trayTypes = stage.tray.map((e) => e.type).toSet();
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

  test('재질 함정 판은 오답 재질로 바꾸면 실패한다', () {
    // (정답 재질, 오답 재질) - 같은 좌표에 반대 재질을 넣은 배치가 1800스텝
    // 안에 클리어되지 않아야 함정이 진짜다.
    const traps = {
      'w5_s04': (PartType.metalBall, PartType.rubberBall),
      'w5_s08': (PartType.rubberBall, PartType.metalBall),
      'w5_s16': (PartType.metalBall, PartType.rubberBall),
      'w5_s17': (PartType.metalBall, PartType.rubberBall),
    };
    traps.forEach((id, pair) {
      final stage = _load(id);
      final swapped = [
        for (final p in stage.solution)
          p.type == pair.$1
              ? Placement(
                  type: pair.$2,
                  x: p.x,
                  y: p.y,
                  angleDeg: p.angleDeg,
                )
              : p,
      ];
      expect(SimWorld.verify(stage, swapped), isFalse, reason: id);
    });
  });
}

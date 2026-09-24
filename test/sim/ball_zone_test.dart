import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/placement_rules.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/stage_data.dart';

void main() {
  // 공을 아무 데나 놓을 수 있으면, 중력으로 목표에 닿는 판은 장치를 만들지
  // 않고 공을 목표 옆에 떨궈 버리면 그냥 깨진다(23차에 11판이 그랬다).
  group('공 놓는 구역', () {
    const zone = BallZone(x: 4.0, y: 3.0, w: 1.6, h: 1.2);

    test('구역 안의 공은 놓을 수 있다', () {
      expect(
        canPlaceAt(const [], PartType.metalBall, 4.0, 3.0, 0, ballZone: zone),
        isTrue,
      );
    });

    test('구역 밖의 공은 막힌다', () {
      expect(
        canPlaceAt(const [], PartType.metalBall, 9.0, 3.0, 0, ballZone: zone),
        isFalse,
      );
      expect(
        placementRejectReason(
          const [],
          PartType.rubberBall,
          4.0,
          6.0,
          0,
          ballZone: zone,
        ),
        contains('drop zone'),
      );
    });

    test('공이 아닌 부품은 구역과 무관하다', () {
      expect(
        canPlaceAt(const [], PartType.plank, 9.0, 3.0, 0, ballZone: zone),
        isTrue,
      );
    });

    test('구역이 없는 판은 아무 제한이 없다', () {
      expect(canPlaceAt(const [], PartType.metalBall, 9.0, 3.0, 0), isTrue);
    });
  });

  // 구역을 넣어 놓고 정답 공이 구역 밖이면 그 판은 풀 수 없게 된다.
  test('구역이 있는 판은 정답 공이 구역 안에 있다', () {
    var checked = 0;
    for (final id in stageOrder) {
      final stage = StageData.fromJson(
        jsonDecode(File('assets/stages/$id.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final zone = stage.ballZone;
      if (zone == null) continue;
      checked++;
      for (final p in stage.solution.where((p) => isBallType(p.type))) {
        expect(
          zone.contains(p.x, p.y),
          isTrue,
          reason: '$id: 정답 공 (${p.x}, ${p.y})이 구역 밖이다',
        );
      }
    }
    expect(checked, greaterThan(0));
  });
}

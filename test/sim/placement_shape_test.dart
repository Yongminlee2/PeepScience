import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/placement_rules.dart';

/// 겹침 판정이 부품의 진짜 모양을 보는지 고정한다.
///
/// 예전에는 모든 부품을 축에 나란한 사각형(AABB) 하나로 바꿔서 봤다. 동그란
/// 톱니는 1x1m 정사각형이 되어 대각선 모서리가 0.2m씩 튀어나왔고, 45도로
/// 기울인 널빤지(2.0x0.24)는 1.584x1.584 상자를 통째로 막았다. 그래서 화면상
/// 분명히 빈 곳인데 부품이 안 놓이는 자리가 생겼다.
///
/// 여기 있는 "예전이면 막히던 자리" 케이스들이 새 기하의 값어치를 재고,
/// "그래도 막힌다" 케이스들이 규칙이 헐거워지지 않았음을 잡는다.
const double _c45 = 0.7071067811865476; // cos 45도 = sin 45도

void main() {
  group('원 ↔ 원: 중심거리로 판정', () {
    final ball = [boxForPart(PartType.rubberBall, 8, 4, 0)]; // r=0.3

    test('딱 붙는 거리(r1+r2=0.6)는 겹침', () {
      expect(canPlaceAt(ball, PartType.rubberBall, 8.6, 4, 0), isFalse);
    });

    test('여유(0.02) 안쪽도 겹침', () {
      expect(canPlaceAt(ball, PartType.rubberBall, 8.615, 4, 0), isFalse);
    });

    test('여유 밖은 배치 가능', () {
      expect(canPlaceAt(ball, PartType.rubberBall, 8.625, 4, 0), isTrue);
    });

    test('대각선으로 비킨 자리는 통과한다 - 사각형 판정이면 막히던 자리', () {
      // dx=dy=0.45라 중심거리는 0.636 > 0.62. 사각형이었다면 두 축 모두
      // 0.45 < 0.62라 거절됐다.
      expect(canPlaceAt(ball, PartType.rubberBall, 8.45, 4.45, 0), isTrue);
    });
  });

  group('원 ↔ 회전 직사각형: 사각형에서 가장 가까운 점까지 재서 판정', () {
    // 45도 널빤지. 이 판자의 AABB는 1.584x1.584 정사각형(반너비 0.792)이다.
    final plank = [boxForPart(PartType.plank, 8, 4, 45)];

    test('판자 면에 수직으로 비킨 모서리 자리는 통과한다 - AABB면 막히던 자리', () {
      // 중심에서 (+0.6,-0.6). 판자 로컬로 보면 길이축 0, 두께축 0.849라
      // 판자 표면에서 0.73m 떨어져 있다. AABB였다면 두 축 모두
      // 0.6 < 0.792+0.3+0.02 = 1.112라 거절됐다.
      expect(canPlaceAt(plank, PartType.rubberBall, 8.6, 3.4, 0), isTrue);
    });

    test('판자 길이 방향으로 붙이면 막힌다', () {
      // 판자 끝(길이축 1.0)에서 0.25m뿐 - 공 반지름 0.3에 못 미친다.
      final d = 1.25;
      expect(
        canPlaceAt(plank, PartType.rubberBall, 8 + d * _c45, 4 + d * _c45, 0),
        isFalse,
      );
    });
  });

  group('회전 직사각형 ↔ 회전 직사각형: 분리축', () {
    // A는 45도, B는 -45도 널빤지를 A의 길이축 위로 d만큼 떨어뜨려 X자로
    // 스치게 둔다. 두 AABB(각 1.584 정사각형)는 어느 거리에서도 겹치므로
    // 예전 규칙은 두 케이스 다 거절했다.
    final a = [boxForPart(PartType.plank, 8, 4, 45)];
    bool placeB(double d) =>
        canPlaceAt(a, PartType.plank, 8 + d * _c45, 4 + d * _c45, -45);

    test('X자로 스치기만 하면 배치된다', () {
      // A의 길이축 위에서 1.2 - 1.0(A 반길이) - 0.12(B 반두께) = 0.08m 간격.
      expect(placeB(1.2), isTrue);
    });

    test('실제로 파고들면 막힌다', () {
      // 같은 축에서 1.10 - 1.12 = -0.02m, 즉 진짜로 겹친다.
      expect(placeB(1.10), isFalse);
    });

    // 위의 X자는 두 판자가 직각이라 네 분리축이 두 방향으로 겹친다 - 한쪽
    // 판자의 축만 보는 구현도 통과해 버린다. 그래서 45도와 15도를 엇갈리게
    // 두고, 오직 B의 두께축(105도)만 갈라 주는 배치를 하나 더 고정한다.
    const c105 = -0.25881904510252074;
    const s105 = 0.9659258262890683;
    bool placeSkew(double d) =>
        canPlaceAt(a, PartType.plank, 8 + d * c105, 4 + d * s105, 15);

    test('한쪽 판자의 축에서만 갈라지는 자리도 통과한다', () {
      // 105도 축에서 0.80 - (A의 0.604 + B의 0.12) = 0.076m 간격.
      // 나머지 세 축은 어느 것도 갈라 주지 않고, 두 AABB도 겹친다.
      expect(placeSkew(0.80), isTrue);
    });

    test('그 축에서 파고들면 막힌다', () {
      // 0.70 - 0.724 = -0.024m.
      expect(placeSkew(0.70), isFalse);
    });
  });

  group('노 달린 톱니: 원과 막대의 합집합', () {
    // 원 r=0.5 + 막대 1.4x0.15. AABB는 1.4x1.0이라 네 모서리가 크게 뜬다.
    final paddle = [boxForPart(PartType.paddleGear, 8, 4, 0)];

    test('막대 쪽으로 다가가면 막힌다 - 원만 봤다면 통과했을 거리', () {
      // 중심거리 0.95는 원의 0.5+0.3+0.02=0.82 밖이지만, 막대 끝에서는
      // 0.25m뿐이다.
      expect(canPlaceAt(paddle, PartType.rubberBall, 8.95, 4, 0), isFalse);
    });

    test('원 쪽으로 다가가면 막힌다 - 막대만 봤다면 통과했을 자리', () {
      // 막대 두께(반 0.075)에서는 0.625m 떨어졌지만 원에서는 0.7m뿐이다.
      expect(canPlaceAt(paddle, PartType.rubberBall, 8, 4.7, 0), isFalse);
    });

    test('막대도 원도 닿지 않는 대각선 자리는 통과한다 - AABB면 막히던 자리', () {
      // (+0.85,+0.5): 원까지 0.99, 막대까지 0.45. AABB(0.7x0.5)였다면
      // 두 축 모두 안쪽이라 거절됐다.
      expect(canPlaceAt(paddle, PartType.rubberBall, 8.85, 4.5, 0), isTrue);
    });
  });

  // 이 예외가 사라지면 톱니 기구를 아예 못 만든다(맞물리려면 겹쳐야 한다).
  test('톱니끼리는 겹침 검사에서 면제된다', () {
    final gear = [boxForPart(PartType.gear, 8, 4, 0)];
    expect(canPlaceAt(gear, PartType.gear, 8.4, 4, 0), isTrue);
  });

  // 새 기하가 예전 AABB보다 항상 관대한지(실제 모양 ⊂ AABB) 무작위로 확인.
  // 이게 깨지면 지금 합법인 100판 정답 중 무엇이든 조용히 불법이 될 수 있다.
  test('새 판정은 예전 사각형 판정보다 절대 엄격해지지 않는다', () {
    final rnd = Random(1234);
    final types = PartType.values;
    for (var i = 0; i < 5000; i++) {
      final ta = types[rnd.nextInt(types.length)];
      final tb = types[rnd.nextInt(types.length)];
      if (isGearFamily(ta) && isGearFamily(tb)) continue;
      final a = boxForPart(ta, 8, 4, rnd.nextDouble() * 360 - 180);
      final b = boxForPart(
        tb,
        8 + rnd.nextDouble() * 4 - 2,
        4 + rnd.nextDouble() * 4 - 2,
        rnd.nextDouble() * 360 - 180,
      );
      final aabb = (a.cx - b.cx).abs() < a.halfX + b.halfX + kOverlapMargin &&
          (a.cy - b.cy).abs() < a.halfY + b.halfY + kOverlapMargin;
      if (overlaps(a, b, kOverlapMargin)) {
        expect(aabb, isTrue,
            reason: '$ta vs $tb: 실제 모양은 겹치는데 AABB는 안 겹친다고 했다');
      }
    }
  });
}

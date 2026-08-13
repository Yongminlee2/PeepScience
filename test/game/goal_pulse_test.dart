import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/hud.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/stage_data.dart';

import '../sim/helpers.dart';

/// 다른 test/game/*_test.dart 파일들의 부트스트랩 + sprite_fallback_test.dart의
/// runAsync 한 줄. 이 펄스 테스트는 (다른 파일들과 달리) placements/selectedIndex
/// 같은 데이터 모델이 아니라 PartView 컴포넌트 자체의 상태(scale)를 직접 읽는다
/// - 목표물(바구니 등)이 이제 실제 PNG 에셋을 가지므로 PartView.onLoad가 진짜
/// 비동기 디코드(Sprite.load)를 타고, 그게 끝나야 컴포넌트가 마운트되어
/// update()를 받기 시작한다. t.pump()만 아무리 반복해도 그 디코드는 절대 안
/// 끝난다(sprite_fallback_test.dart가 40회까지 직접 확인한 것과 동일한 이유) -
/// runAsync로 진짜 이벤트 루프를 한 번 돌려야 한다.
Future<PiyakGame> _pumpGame(WidgetTester t, StageData s) async {
  t.view.physicalSize = const Size(1600, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final game = PiyakGame(s);
  await t.pumpWidget(GameWidget(game: game));
  await t.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  for (var i = 0; i < 10; i++) {
    await t.pump();
  }
  return game;
}

/// real_touch_test.dart의 _driftTap과 동일 - 목표 배지도 다른 모든 탭처럼
/// PiyakGame의 합성 탭 경로(_dispatchTap)를 거치므로, 실기기 손가락 드리프트를
/// 흉내내는 이 헬퍼로 눌러야 진짜 탭 경로(GoalBadge.activate)를 검증한다.
Future<void> _driftTap(
  WidgetTester t,
  Offset pos, {
  Offset drift = const Offset(4, 3),
}) async {
  final gesture = await t.startGesture(pos);
  await gesture.moveBy(drift);
  await gesture.up();
  await t.pump(const Duration(milliseconds: 350));
}

/// GoalBadge의 화면 중심 - 자체 레이아웃 상수에서 유도(다른 테스트 파일들의
/// _runButtonCenter/_slot0Center와 같은 이유: hud.dart와 어긋나지 않게).
const Offset _goalBadgeCenter = Offset(
  GoalBadge.margin + GoalBadge.cardSize / 2,
  GoalBadge.margin + GoalBadge.cardSize / 2,
);

/// 목표(바구니) 하나만 있는 최소 스테이지 - solution은 StageData 검증상
/// 비어 있을 수 없어 더미로 채운다(실제로 놓이지는 않는다).
StageData _basketStage() => stage(
      '{"type":"basket","x":8,"y":6,"angle":0}',
      '',
      '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
    );

/// PiyakGame.update의 accumulator와 무관하게, 펄스 타이머([PartView]의 실제
/// wall-clock dt 누적)를 확실히 다 지나가도록 100ms씩 나눠 pump한다.
Future<void> _pumpSeconds(WidgetTester t, double seconds) async {
  const step = Duration(milliseconds: 100);
  final steps = (seconds * 1000 / step.inMilliseconds).ceil();
  for (var i = 0; i < steps; i++) {
    await t.pump(step);
  }
}

void main() {
  testWidgets('에딧 모드 진입 시 목표물이 펄스하고, 다 끝나면 스케일이 1.0으로 돌아온다',
      (t) async {
    final s = _basketStage();
    final game = await _pumpGame(t, s);

    // onLoad에서 이미 예약된 펄스 - 초반 몇 프레임 안에 스케일이 1.0을
    // 벗어나야 한다(아무 일도 안 일어나는 회귀 방지).
    await t.pump(const Duration(milliseconds: 150));
    expect(game.goalPulseScale(), isNotNull);
    expect(game.goalPulseScale(), greaterThan(1.0));

    // 두 번의 범프(총 0.4*2=0.8초)를 넉넉히 다 지나면 다시 1.0으로
    // 안정되고, 크래시 없이 pump가 계속 통과한다.
    await _pumpSeconds(t, 1.0);
    expect(game.goalPulseScale(), closeTo(1.0, 0.001));
  });

  testWidgets('목표 배지를 탭하면 펄스가 다시 재생된다', (t) async {
    final s = _basketStage();
    final game = await _pumpGame(t, s);
    // 최초 진입 펄스를 완전히 끝낸 상태를 기준선으로 삼는다.
    await _pumpSeconds(t, 1.0);
    expect(game.goalPulseScale(), closeTo(1.0, 0.001));

    await _driftTap(t, _goalBadgeCenter);
    await t.pump(const Duration(milliseconds: 150));

    expect(game.goalPulseScale(), greaterThan(1.0));

    await _pumpSeconds(t, 1.0);
    expect(game.goalPulseScale(), closeTo(1.0, 0.001));
  });

  testWidgets('run 모드에서는 목표 배지를 탭해도 펄스가 재생되지 않는다', (t) async {
    final s = _basketStage();
    final game = await _pumpGame(t, s);
    await _pumpSeconds(t, 1.0); // 최초 진입 펄스 소진
    expect(game.goalPulseScale(), closeTo(1.0, 0.001));

    game.startRun();
    await t.pump();

    await _driftTap(t, _goalBadgeCenter);
    await t.pump(const Duration(milliseconds: 150));

    expect(game.goalPulseScale(), closeTo(1.0, 0.001));
  });
}

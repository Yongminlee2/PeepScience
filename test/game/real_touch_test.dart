import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/hud.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/stage_data.dart';

import '../sim/helpers.dart';

// 실기기 재현: 아래 모든 제스처는 down과 up 사이에 몇 px씩 드리프트한다 - 실기기에서
// `adb shell input swipe x y x+6 y+3 80`(6px 드리프트)이 탭을 전부 죽이고
// `adb shell input tap`(이동 0)만 통과했던 것과 같은 조건. 이 저장소의 다른 모든
// 테스트 파일은 `tester.tapAt`/`tester.dragFrom(..., touchSlopX: 0, touchSlopY: 0)`
// 로 이동이 정확히 0이라 이 버그를 애초에 재현하지 못했다(piyak_game.dart의
// "Real-finger tap synthesis" 주석 참고).

Offset _worldPx(double xM, double yM) =>
    Offset(xM * PiyakGame.ppm, yM * PiyakGame.ppm);

/// placement_test.dart/edit_test.dart/run_flow_test.dart와 동일한 부트스트랩.
Future<PiyakGame> _pumpGame(WidgetTester t, StageData s) async {
  t.view.physicalSize = const Size(1600, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final game = PiyakGame(s);
  await t.pumpWidget(GameWidget(game: game));
  for (var i = 0; i < 10; i++) {
    await t.pump();
  }
  return game;
}

// run_flow_test.dart의 _runButtonCenter와 동일 - hud.dart의 레이아웃 상수에서
// 직접 유도해 값이 어긋나지 않게 한다.
const Offset _runButtonCenter = Offset(
  1600 - RunToggleButton.margin - RunToggleButton.buttonDiameter / 2,
  900 -
      TrayBar.barHeight -
      RunToggleButton.margin -
      RunToggleButton.buttonDiameter / 2,
);

const Offset _slot0Center = Offset(
  TrayBar.slotGap + TrayBar.slotSize / 2,
  900 - TrayBar.barHeight + TrayBar.slotMarginTop + TrayBar.slotSize / 2,
);

/// 실손가락처럼 몇 px 드리프트하는 탭: down -> [drift]만큼 이동 -> up. 기본
/// (4,3)은 15px/300ms 탭 판정 문턱 안쪽이지만 0은 아니다 - 0이면 이 파일이
/// 재현하려는 버그(어떤 이동이든 드래그 인식기가 아비터를 가져가는 것) 자체가
/// 발동하지 않는다.
Future<void> _driftTap(
  WidgetTester t,
  Offset pos, {
  Offset drift = const Offset(4, 3),
}) async {
  final gesture = await t.startGesture(pos);
  await gesture.moveBy(drift);
  await gesture.up();
  // 350ms > flame의 MultiTapGestureRecognizer 롱탭 타이머(기본 300ms) - 다른
  // 모든 테스트 파일의 _tap/_drag와 동일한 이유(그 타이머가 안 없어지면
  // flutter_test의 FakeAsync 바인딩이 teardown에서 pending Timer로 실패한다).
  await t.pump(const Duration(milliseconds: 350));
}

StageData _trivialStage() => stage(
      '{"type":"basket","x":8,"y":6,"angle":0}',
      '{"type":"rubber_ball","count":1}',
      '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
    );

/// run_flow_test.dart의 _pumpUntilCleared와 동일.
Future<void> _pumpUntilCleared(
  WidgetTester t,
  PiyakGame game, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps && game.sim?.cleared != true; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
}

void main() {
  testWidgets('드리프트가 있는 탭도 ▶을 눌러 run 모드로 전환한다', (t) async {
    final s = _trivialStage();
    final game = await _pumpGame(t, s);
    game.addPlacement(s.solution.single);
    await t.pump();

    await _driftTap(t, _runButtonCenter);

    expect(game.mode, GameMode.run);
  });

  testWidgets('드리프트가 있는 탭도 배치된 부품을 선택한다', (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(
        Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    await _driftTap(t, _worldPx(8, 4));

    expect(game.selectedIndex, 0);
  });

  testWidgets('클리어 후 오버레이 다시 버튼도 드리프트 탭으로 edit 모드에 복귀한다', (t) async {
    final s = _trivialStage();
    final game = await _pumpGame(t, s);
    game.addPlacement(s.solution.single);
    await t.pump();

    await _driftTap(t, _runButtonCenter);
    await _pumpUntilCleared(t, game);
    expect(game.sim!.cleared, isTrue);

    await _driftTap(t, WinOverlay.retryButtonCenter);

    expect(game.mode, GameMode.edit);
  });

  testWidgets('15px 넘는 진짜 드래그는 트레이 부품을 배치하고 탭으로 처리되지 않는다', (t) async {
    final s = stage(
      '',
      '{"type":"plank","count":1}',
      '{"type":"plank","x":8,"y":4,"angle":0}',
    );
    final game = await _pumpGame(t, s);
    final drop = _worldPx(8, 4);

    final gesture = await t.startGesture(_slot0Center);
    await gesture.moveTo(drop);
    await gesture.up();
    await t.pump(const Duration(milliseconds: 350));

    expect(game.placements.length, 1);
    expect(game.placements.single.type, PartType.plank);
    expect(game.placements.single.x, closeTo(8, 0.01));
    expect(game.placements.single.y, closeTo(4, 0.01));
  });
}

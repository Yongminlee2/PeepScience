import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/input.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/stage_data.dart';

import '../sim/helpers.dart';

Offset _worldPx(double xM, double yM) =>
    Offset(xM * PiyakGame.ppm, yM * PiyakGame.ppm);

/// Same bounded-pump pattern as test/game/placement_test.dart -
/// game.ready() deadlocks under flutter_test's FakeAsync (see that file's
/// own comment for why).
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

/// Taps at [pos] and pumps past flame's MultiTapGestureRecognizer long-tap
/// timer (TapConfig.longTapDelay, default 300ms) so it fires and clears
/// itself instead of leaking a still-pending Timer past this test's
/// teardown (flutter_test's FakeAsync-based binding asserts none are
/// pending once the widget tree is disposed).
Future<void> _tap(WidgetTester t, Offset pos) async {
  await t.tapAt(pos);
  await t.pump(const Duration(milliseconds: 350));
}

/// Drags from [from] by [delta] and pumps past the same long-tap timer
/// _tap does - every pointer-down (drag or tap alike) starts one, per
/// flame's MultiTapGestureRecognizer, regardless of which gesture it turns
/// out to be.
Future<void> _drag(WidgetTester t, Offset from, Offset delta) async {
  await t.dragFrom(from, delta, touchSlopX: 0, touchSlopY: 0);
  await t.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('배치된 널빤지를 탭하면 선택되고, 핸들을 드래그하면 5도 배수로 회전한다',
      (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    await _tap(t, _worldPx(8, 4));
    expect(game.selectedIndex, 0);

    // Handle starts at angleDeg 0 -> straight to the right of center. Drag
    // it to straight below center -> atan2 gives exactly 90 deg, already a
    // multiple of 5 so the snap is unambiguous.
    final handle = rotateHandleWorldPos(game.placements[0]);
    final handlePx = _worldPx(handle.x, handle.y);
    final target = _worldPx(8, 4 + selectionRingRadiusM(PartType.plank));
    await _drag(t, handlePx, target - handlePx);

    final angle = game.placements[0].angleDeg;
    expect(angle % 5, closeTo(0, 0.0001));
    expect(angle, isNot(closeTo(0, 0.0001)));
    expect(game.rotatingIndex, isNull);
  });

  testWidgets('선택된 부품의 삭제 X를 탭하면 배치가 제거되고 트레이 개수가 복구된다',
      (t) async {
    final s = stage('', '{"type":"plank","count":2}',
        '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0));
    await t.pump();
    // 트레이 원본 개수(2)에서 배치 1개만큼 줄어든 상태가 삭제 후 복구되는지 볼
    // 기준선.
    final originalRemaining =
        2 - game.placements.where((p) => p.type == PartType.plank).length;
    expect(originalRemaining, 1);

    await _tap(t, _worldPx(8, 4));
    expect(game.selectedIndex, 0);

    final del = deleteButtonWorldPos(game.placements[0]);
    await _tap(t, _worldPx(del.x, del.y));

    expect(game.placements, isEmpty);
    expect(game.selectedIndex, isNull);
    // 트레이 잔여 개수는 placements에서 파생되므로(hud.dart) 원본 2로 복구됨.
    final restoredRemaining =
        2 - game.placements.where((p) => p.type == PartType.plank).length;
    expect(restoredRemaining, 2);
  });

  testWidgets('공은 선택·삭제는 되지만 회전 핸들은 없다', (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(
        Placement(type: PartType.rubberBall, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    await _tap(t, _worldPx(8, 4));
    expect(game.selectedIndex, 0);

    // 회전 가능한 부품이었다면 핸들을 잡았을 바로 그 지점에서 같은 제스처를
    // 시도해도, 공은 rotatable이 아니므로 회전 드래그가 아예 시작되지 않아야
    // 한다.
    final wouldBeHandle = rotateHandleWorldPos(game.placements[0]);
    final handlePx = _worldPx(wouldBeHandle.x, wouldBeHandle.y);
    final target =
        _worldPx(8, 4 + selectionRingRadiusM(PartType.rubberBall));
    await _drag(t, handlePx, target - handlePx);
    expect(game.placements[0].angleDeg, 0);
    expect(game.rotatingIndex, isNull);

    final del = deleteButtonWorldPos(game.placements[0]);
    await _tap(t, _worldPx(del.x, del.y));
    expect(game.placements, isEmpty);
  });

  testWidgets('위쪽 경계(y=0.3)에 놓인 부품도 삭제 X를 탭할 수 있다', (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    // kFieldMinY(0.3)는 합법 배치 위치 - 이 y에서도 삭제 X 히트서클 전체가
    // 화면 밖(y<0)으로 밀려나면 안 된다 (리뷰 finding 1).
    game.addPlacement(Placement(type: PartType.plank, x: 8, y: 0.3, angleDeg: 0));
    await t.pump();

    await _tap(t, _worldPx(8, 0.3));
    expect(game.selectedIndex, 0);

    // 실제 렌더된 위치에서 그대로 탭 - deleteButtonWorldPos가 클램프를
    // 반영하지 않으면 이 좌표 자체가 화면 밖(음수 y)이 되어 앱이라면 애초에
    // 탭할 수 없는 좌표가 된다는 것이 finding의 핵심.
    final del = deleteButtonWorldPos(game.placements[0]);
    expect(del.y, greaterThanOrEqualTo(0));
    await _tap(t, _worldPx(del.x, del.y));

    expect(game.placements, isEmpty);
    expect(game.selectedIndex, isNull);
  });

  testWidgets(
      'removePlacement은 낮은 인덱스 제거 시 selectedIndex/rotatingIndex를 당기고, 같은 인덱스면 해제한다',
      (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.plank, x: 1, y: 1, angleDeg: 0));
    game.addPlacement(Placement(type: PartType.plank, x: 2, y: 2, angleDeg: 0));
    game.addPlacement(Placement(type: PartType.plank, x: 3, y: 3, angleDeg: 0));
    await t.pump();

    // 회전 드래그 중(rotatingIndex=2)인 부품을, 다른 손가락이 앞쪽 인덱스를
    // 삭제해 밀어내는 멀티터치 시나리오를 재현 - 두 필드 모두 같은 부품(원래
    // index 2)을 계속 가리켜야 한다.
    game.selectedIndex = 2;
    game.rotatingIndex = 2;

    game.removePlacement(0);
    expect(game.selectedIndex, 1);
    expect(game.rotatingIndex, 1);

    // 이제 index 1이 바로 그 부품 - 이걸 지우면 두 필드 다 null이어야 한다
    // (다른 부품으로 잘못 넘어가면 안 됨).
    game.removePlacement(1);
    expect(game.selectedIndex, isNull);
    expect(game.rotatingIndex, isNull);
  });
}

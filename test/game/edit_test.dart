import 'dart:math';
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

  // UX 개편 B: 배치된 부품 드래그 이동 (owner pain point: "막대기를 한번
  // 놓으면 드래그해서 이동도 못 해").
  testWidgets(
      '배치된 널빤지를 중심이 아닌 지점에서 잡고 드래그하면 잡은 오프셋을 유지한 채 이동하고 계속 선택된 상태다',
      (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    // 중심(8,4)이 아니라 왼쪽으로 0.5m 치우친 지점을 잡는다 - 판 폭(2.0m)
    // 절반(1.0m) 안쪽이라 여전히 발자국 내부. 사전 탭 없이 곧바로 드래그만
    // 하는 것도 이 테스트의 일부 - "잡으면 바로 선택"(Improvement B).
    final grab = _worldPx(7.5, 4);
    const dragDeltaPx = Offset(40, 0); // 15px 탭 문턱보다 커서 이동으로 처리
    await _drag(t, grab, dragDeltaPx);

    expect(game.selectedIndex, 0);
    final p = game.placements[0];
    // 40px = 0.4m 이동, 잡은 오프셋(중심 기준 -0.5,0)은 그대로 유지된다 -
    // 중심이 손가락 위치로 튀지 않는다.
    expect(p.x, closeTo(8.4, 0.01));
    expect(p.y, closeTo(4, 0.01));
  });

  testWidgets('배치된 부품을 다른 부품과 겹치는 자리로 옮기면 원래 위치로 되돌아간다', (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.plank, x: 4, y: 4, angleDeg: 0));
    game.addPlacement(Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    final grab = _worldPx(4, 4); // 첫 번째 판(index 0) 중심을 그대로 잡는다
    final overlapTarget = _worldPx(8, 4); // 두 번째 판과 정확히 겹치는 자리
    await _drag(t, grab, overlapTarget - grab);

    final p = game.placements[0];
    expect(p.x, closeTo(4, 0.01));
    expect(p.y, closeTo(4, 0.01));
    expect(game.selectedIndex, 0); // 되돌아가도 선택은 유지된다
  });

  // UX 개편 C: 손잡이가 아니라 고리 밴드 아무 곳이나 드래그해도 회전.
  testWidgets('선택된 부품은 손잡이가 아니라 고리 밴드를 드래그해도 5도 배수로 회전한다', (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    await _tap(t, _worldPx(8, 4));
    expect(game.selectedIndex, 0);

    // 손잡이(각도 0 방향 - 중심에서 오른쪽)가 아니라 고리에서 45도 떨어진
    // 밴드 위 지점에서 드래그를 시작한다 - 손잡이 히트반경(kHandleHitRadiusM)
    // 밖임을 먼저 확인해, 밴드 로직 자체가 회전을 시작시켰다는 걸 보장한다.
    final ringRadius = selectionRingRadiusM(PartType.plank);
    final bandGrab = Vector2(
        8 + ringRadius * cos(pi / 4), 4 + ringRadius * sin(pi / 4));
    final handle = rotateHandleWorldPos(game.placements[0]);
    expect((bandGrab - handle).length, greaterThan(kHandleHitRadiusM));

    final bandGrabPx = _worldPx(bandGrab.x, bandGrab.y);
    final target = _worldPx(8, 4 + ringRadius); // 90도 지점 - 5의 배수라 스냅이 뚜렷함
    await _drag(t, bandGrabPx, target - bandGrabPx);

    final angle = game.placements[0].angleDeg;
    expect(angle % 5, closeTo(0, 0.0001));
    expect(angle, isNot(closeTo(0, 0.0001)));
    expect(game.rotatingIndex, isNull);
  });

  // 회귀 방지: 선풍기(fan)는 고리 반지름이 작아(선택 반지름 ~0.65m) 밴드
  // 범위(반지름 ±0.3m)가 삭제 X의 고정 오프셋(0.6m)을 모든 회전각에서
  // 항상 감싼다 - _onDeleteButton 가드가 없으면 선택된 선풍기의 삭제 X가
  // 회전각과 무관하게 영원히 눌리지 않게 된다.
  testWidgets('선풍기를 선택한 상태에서도 삭제 X는 고리 밴드에 가리지 않고 항상 눌린다', (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.fan, x: 8, y: 4, angleDeg: 0));
    await t.pump();

    await _tap(t, _worldPx(8, 4));
    expect(game.selectedIndex, 0);

    final del = deleteButtonWorldPos(game.placements[0]);
    await _tap(t, _worldPx(del.x, del.y));

    expect(game.placements, isEmpty);
    expect(game.selectedIndex, isNull);
  });

  // 리뷰 Critical 1 회귀 방지: 손가락 A가 부품을 불법 위치로 옮기는 도중
  // 손가락 B가 다른 부품의 발자국을 건드려도 A의 이동 소유권을 가로채면
  // 안 된다 - 가로채면 A가 옮기던 부품은 release-시 canPlaceAt 재검사/되돌림
  // 없이 방치되고, 오히려 B가 놓을 때 엉뚱하게 그 검사를 대신 받게 된다.
  testWidgets(
      '한 손가락이 부품을 불법 위치로 옮기는 도중 다른 손가락이 별개 부품을 건드려도 이동 소유권을 가로채지 않는다',
      (t) async {
    final s = stage('', '', '{"type":"plank","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(
        Placement(type: PartType.plank, x: 2, y: 2, angleDeg: 0)); // idx0: A가 옮길 부품
    game.addPlacement(
        Placement(type: PartType.plank, x: 8, y: 4, angleDeg: 0)); // idx1: B가 건드릴 부품
    game.addPlacement(
        Placement(type: PartType.plank, x: 12, y: 4, angleDeg: 0)); // idx2: 겹칠 대상(블로커)
    await t.pump();

    // 손가락 A: idx0 중심을 잡는다.
    final gestureA = await t.startGesture(_worldPx(2, 2));
    await t.pump();
    expect(game.movingIndex, 0);

    // idx2와 정확히 겹치는 불법 위치로 이동 - 아직 놓지 않는다.
    await gestureA.moveTo(_worldPx(12, 4));
    await t.pump();
    expect(game.placements[0].x, closeTo(12, 0.01));
    expect(game.placements[0].y, closeTo(4, 0.01));

    // 손가락 B: A가 여전히 진행 중인 동안 idx1의 발자국(자기 중심)을 짧게
    // 건드린다 - 이 순간 movingIndex가 idx1로 가로채이면 안 된다(Critical 1).
    final gestureB = await t.startGesture(_worldPx(8, 4));
    await t.pump();
    expect(game.movingIndex, 0); // 여전히 A(idx0) 소유 - 가로채기 없음
    expect(game.placements[1].x, closeTo(8, 0.01));
    expect(game.placements[1].y, closeTo(4, 0.01));
    await gestureB.up();
    await t.pump(const Duration(milliseconds: 350));

    // B를 놓은 뒤에도 idx1은 전혀 움직이지 않았어야 한다.
    expect(game.placements[1].x, closeTo(8, 0.01));
    expect(game.placements[1].y, closeTo(4, 0.01));

    // A를 놓는다 - idx2와 겹치는 불법 위치였으므로 잡기 전 위치(2,2)로
    // 되돌아가야 한다(가로채기가 있었다면 이 되돌림 자체가 안 일어났을 것).
    await gestureA.up();
    await t.pump(const Duration(milliseconds: 350));

    expect(game.placements[0].x, closeTo(2, 0.01));
    expect(game.placements[0].y, closeTo(2, 0.01));
    expect(game.movingIndex, isNull);
  });
}

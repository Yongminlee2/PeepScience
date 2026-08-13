import 'dart:math';
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/hud.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/stage_data.dart';

import '../sim/helpers.dart';

// Slot 0's on-screen center, derived from TrayBar's own layout constants
// (not duplicated magic numbers) so this stays in sync with hud.dart.
const Offset _slot0Center = Offset(
  TrayBar.slotGap + TrayBar.slotSize / 2,
  900 - TrayBar.barHeight + TrayBar.slotMarginTop + TrayBar.slotSize / 2,
);

Offset _worldPx(double xM, double yM) =>
    Offset(xM * PiyakGame.ppm, yM * PiyakGame.ppm);

/// Pumps [s] into a 1600x900-at-1x test view, so that screen px (what
/// tester.dragFrom uses) equals the game's own logical/world px 1:1 - the
/// FixedResolutionViewport's scale becomes exactly 1 and its letterbox
/// offset becomes exactly 0 when the canvas already matches its virtual
/// resolution (see FixedResolutionViewport.onViewportResize in the
/// installed flame source). Then pumps several more frames so every
/// pending Flame lifecycle event fully settles (TrayBar -> slots -> each
/// slot's DragCallbacks mounting the drag dispatcher -> the dispatcher
/// registering the gesture recognizer -> GameWidget rebuilding its
/// RawGestureDetector with that recognizer) before any gesture is sent.
///
/// Deliberately NOT `game.ready()`: that helper awaits a bare
/// `Future<void>.delayed(Duration.zero)`, but `flutter test` runs widget
/// tests inside a `FakeAsync` zone (AutomatedTestWidgetsFlutterBinding,
/// see flutter_test's binding.dart) where Timer-backed futures - which is
/// what Future.delayed always is, even at Duration.zero - only fire when
/// something explicitly elapses the fake clock. Nothing does that while a
/// bare `await game.ready()` just sits there, so it deadlocks forever
/// (confirmed empirically: CPU-active but zero output/progress across
/// repeated checks). `tester.pump()` elapses the fake clock itself, so a
/// bounded loop of those is the safe way to flush the queue instead.
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

/// Drags from [from] by [delta], then pumps 350ms (> flame's
/// TapConfig.longTapDelay, default 300ms). Task 8 gave PiyakGame its own
/// TapCallbacks, and flame's MultiTapGestureRecognizer starts a long-tap
/// timer on EVERY pointer-down game-wide - drag or tap alike, not just
/// taps - so a drag gesture now also needs to pump past it, or
/// flutter_test's FakeAsync-based binding fails teardown on a still-pending
/// Timer (see edit_test.dart's identical _drag helper for Task 8's own
/// drags).
Future<void> _drag(WidgetTester t, Offset from, Offset delta) async {
  await t.dragFrom(from, delta, touchSlopX: 0, touchSlopY: 0);
  await t.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('트레이에서 끌어다 놓으면 배치되고 개수가 준다', (t) async {
    final s = stage(
      '',
      '{"type":"plank","count":2}',
      '{"type":"plank","x":8,"y":4,"angle":0}',
    );
    final game = await _pumpGame(t, s);

    final drop = _worldPx(8, 4);
    await _drag(t, _slot0Center, drop - _slot0Center);

    expect(game.placements.length, 1);
    expect(game.placements.single.type, PartType.plank);
    expect(game.placements.single.x, closeTo(8, 0.01));
    expect(game.placements.single.y, closeTo(4, 0.01));
  });

  testWidgets('기존 부품과 겹치면 배치되지 않는다', (t) async {
    final s = stage(
      '',
      '{"type":"plank","count":2}',
      '{"type":"plank","x":8,"y":4,"angle":0}',
    );
    final game = await _pumpGame(t, s);
    final drop = _worldPx(8, 4);

    await _drag(t, _slot0Center, drop - _slot0Center);
    expect(game.placements.length, 1);

    // Same spot again: remaining count is still 1 so the drag can start,
    // but the drop should be rejected for overlapping the part just placed.
    await _drag(t, _slot0Center, drop - _slot0Center);
    expect(game.placements.length, 1);
  });

  testWidgets('톱니는 이웃 톱니에 스냅된다', (t) async {
    final s = stage(
      '{"type":"motor_gear","x":8,"y":4,"angle":0}',
      '{"type":"gear","count":1}',
      '{"type":"gear","x":8,"y":4,"angle":0}',
    );
    final game = await _pumpGame(t, s);

    // 0.8m from the preset motorGear - inside the r1+r2+0.15 = 1.15m catch
    // range, so this should snap rather than land raw.
    final drop = _worldPx(8.8, 4);
    await _drag(t, _slot0Center, drop - _slot0Center);

    expect(game.placements.length, 1);
    final p = game.placements.single;
    final dist = sqrt(pow(p.x - 8, 2) + pow(p.y - 4, 2));
    expect(dist, closeTo(0.97, 0.01)); // r1+r2-0.03 = 0.5+0.5-0.03
  });

  // UX 개편 A: 트레이 드롭 자동 선택.
  testWidgets('트레이에서 끌어다 놓으면 새로 배치된 부품이 자동으로 선택된다', (t) async {
    final s = stage(
      '',
      '{"type":"plank","count":1}',
      '{"type":"plank","x":8,"y":4,"angle":0}',
    );
    final game = await _pumpGame(t, s);

    final drop = _worldPx(8, 4);
    await _drag(t, _slot0Center, drop - _slot0Center);

    expect(game.placements.length, 1);
    expect(game.selectedIndex, 0);
  });

  // UX 개편 B: 배치된 톱니 이동도 트레이 드롭과 같은 스냅을 탄다.
  testWidgets('배치된 톱니를 옮겨 이웃 톱니 옆에 놓으면 반지름 합만큼 스냅된다', (t) async {
    final s = stage(
      '{"type":"motor_gear","x":8,"y":4,"angle":0}',
      '',
      '{"type":"gear","x":3,"y":4,"angle":0}',
    );
    final game = await _pumpGame(t, s);
    // 트레이가 아니라 이미 배치된 부품을 직접 잡아 옮기는 시나리오라
    // addPlacement로 미리 놓아 둔다(edit_test.dart와 동일한 관례).
    game.addPlacement(Placement(type: PartType.gear, x: 3, y: 4, angleDeg: 0));
    await t.pump();

    // 톱니 중심을 그대로 잡고, 프리셋 motorGear에서 0.8m 거리(스냅 캐치
    // 범위 1.15m 안쪽)까지 끌고 간다 - 위 트레이 스냅 테스트와 같은 기하.
    final grab = _worldPx(3, 4);
    final dropNear = _worldPx(8.8, 4);
    await _drag(t, grab, dropNear - grab);

    expect(game.placements.length, 1);
    final p = game.placements.single;
    expect(p.type, PartType.gear);
    final dist = sqrt(pow(p.x - 8, 2) + pow(p.y - 4, 2));
    expect(dist, closeTo(0.97, 0.01)); // r1+r2-0.03 = 0.5+0.5-0.03
  });

  // 리뷰 Important 2 / Minor 3 회귀 방지: 맞물린 톱니 3개 중 가운데를
  // 탭(15px 문턱 안쪽)만 해도 release-시 snapGearPosition이 돌면 안 된다 -
  // 돌면 "가장 가까운 이웃"이 지금과 다른 톱니로 잡혀 그냥 선택만 하려던
  // 탭이 조용히 기구 연결을 바꿔 버린다.
  testWidgets('맞물린 톱니 3개 중 가운데를 탭 수준으로만 건드려도 재스냅 없이 위치가 그대로다', (t) async {
    final s = stage('', '', '{"type":"gear","x":0,"y":0,"angle":0}');
    final game = await _pumpGame(t, s);
    game.addPlacement(Placement(type: PartType.gear, x: 7, y: 4, angleDeg: 0)); // idx0
    game.addPlacement(
        Placement(type: PartType.gear, x: 7.97, y: 4, angleDeg: 0)); // idx1: 가운데
    game.addPlacement(
        Placement(type: PartType.gear, x: 8.94, y: 4, angleDeg: 0)); // idx2
    await t.pump();

    final before = [for (final p in game.placements) (p.x, p.y)];

    // 15px 문턱 안쪽의 미세한 드리프트(실손가락 탭을 흉내냄, real_touch_test.dart의
    // _driftTap과 같은 취지) - handleEditMoveDragUpdate가 최소 한 번은 돌아
    // 라이브 위치가 실제로 바뀌었다가, 놓을 때 정확히 원위치로 복귀하는지까지
    // 검증한다(zero-movement 탭보다 더 강한 증거).
    final mid = _worldPx(7.97, 4);
    await _drag(t, mid, const Offset(4, 3));

    expect(game.selectedIndex, 1);
    // closeTo, 다른 모든 위치 검증과 동일한 이유(placement_test.dart 위쪽
    // 테스트들 참고) - Vector2(vector_math)는 내부적으로 float32라 grab 시점의
    // Vector2(p.x,p.y) 캡처 한 번만으로도 7.97 같은 소수 리터럴이
    // 7.96999979019165로 반올림된다. 검증하려는 것은 "재스냅이 안 일어났다"
    // (스냅이 일어났다면 오차가 kGearSnapSlack 규모인 0.03m대로 훨씬 크다)
    // 이지 비트 단위 동일성이 아니다.
    for (var i = 0; i < 3; i++) {
      expect(game.placements[i].x, closeTo(before[i].$1, 0.001));
      expect(game.placements[i].y, closeTo(before[i].$2, 0.001));
    }
  });
}

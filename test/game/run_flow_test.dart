import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/hud.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/stage_data.dart';

import '../sim/helpers.dart';

/// Same bounded-pump pattern as test/game/placement_test.dart /
/// edit_test.dart - game.ready() deadlocks under flutter_test's FakeAsync
/// (see placement_test.dart's own comment for why).
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
/// timer (TapConfig.longTapDelay, default 300ms), same as edit_test.dart's
/// _tap - PiyakGame's own TapCallbacks starts one on every pointer-down
/// game-wide, tap or drag alike.
Future<void> _tap(WidgetTester t, Offset pos) async {
  await t.tapAt(pos);
  await t.pump(const Duration(milliseconds: 350));
}

/// Runs the sim forward - via the real widget/ticker pump loop, not a
/// direct game.update() call, so this exercises exactly what a device
/// frame would drive - until `game.sim!.cleared` or [maxPumps] is hit.
/// PiyakGame.update's own accumulator caps at 0.25s of sim time per call
/// regardless of the wall-clock duration a single pump elapses, so 250ms
/// per pump is already the most productive size (any larger is wasted).
Future<void> _pumpUntilCleared(
  WidgetTester t,
  PiyakGame game, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps && game.sim?.cleared != true; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  // `cleared` flipping merely *schedules* WinOverlay for addition - Flame's
  // Component.add() queues it ("placed into a queue, and then added later,
  // after it has finished loading, but no sooner than on the next game
  // tick" - see component.dart's own doc comment). A few zero-duration
  // settle pumps (same idea as _pumpGame's post-mount loop) let that queued
  // add, its onLoad, and its own children's queued adds actually land
  // before callers inspect camera.viewport.children.
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
}

/// Pumps until [game.mode] flips back to edit (the dead-run auto-reset) or
/// [maxPumps] is hit - same 250ms-pump budget reasoning as
/// [_pumpUntilCleared] (fall-to-destroy is ~1.4s, plus the ~1.2s grace
/// timer, plus settle margin).
Future<void> _pumpUntilEdit(
  WidgetTester t,
  PiyakGame game, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps && game.mode != GameMode.edit; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

// RunToggleButton's on-screen center, derived from its own layout constants
// (not duplicated magic numbers) so this stays in sync with hud.dart - same
// approach as placement_test.dart's _slot0Center for TrayBar.
const Offset _runButtonCenter = Offset(
  1600 - RunToggleButton.margin - RunToggleButton.buttonDiameter / 2,
  900 -
      TrayBar.barHeight -
      RunToggleButton.margin -
      RunToggleButton.buttonDiameter / 2,
);

/// Trivially-clearable stage: a rubber ball placed (as the stage's own
/// authored `solution`) directly above a basket with nothing in the way, so
/// the pump loop in each test below only needs a handful of iterations to
/// reach `cleared` (straight ~3.5m drop, no ramp/plank to build first).
StageData _trivialStage() => stage(
      '{"type":"basket","x":8,"y":6,"angle":0}',
      '{"type":"rubber_ball","count":1}',
      '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
    );

/// Reproduces the first-playtest dead-run: a preset ball with nothing under
/// it (no basket at all, so `cleared` can never latch) falls straight down
/// and is swept by SimWorld.step's off-bounds destroy queue - the exact
/// "press ▶ with nothing placed" scenario. tray/solution are dummy data
/// (StageData requires a non-empty solution array) never placed by the test.
StageData _deadRunStage() => stage(
      '{"type":"rubber_ball","x":8,"y":1,"angle":0}',
      '{"type":"plank","count":1}',
      '{"type":"plank","x":10,"y":5,"angle":0}',
    );

void main() {
  testWidgets(
      '실행 버튼을 탭하면 run 모드로 전환되고, 클리어되면 오버레이가 뜨며 onCleared가 스테이지 id로 '
      '1회 호출되고 sim은 더 이상 진행되지 않는다', (t) async {
    final s = _trivialStage();
    final game = await _pumpGame(t, s);
    // 솔루션을 placements로 주입 - 실제 플레이어가 정답을 배치한 상태를 흉내낸다.
    game.addPlacement(s.solution.single);
    await t.pump();

    var clearedCount = 0;
    String? clearedId;
    game.onCleared = (id) {
      clearedCount++;
      clearedId = id;
    };

    await _tap(t, _runButtonCenter);
    expect(game.mode, GameMode.run);

    await _pumpUntilCleared(t, game);

    expect(game.sim, isNotNull);
    expect(game.sim!.cleared, isTrue,
        reason: '이 pump 예산 안에 클리어되지 않음 - 낙하 스테이지 튜닝을 확인');
    expect(clearedCount, 1);
    expect(clearedId, s.id);
    expect(game.camera.viewport.children.whereType<WinOverlay>().length, 1);

    // 클리어 후에는 sim이 더 이상 진행되면 안 된다(정지/freeze).
    final frozenStepCount = game.sim!.stepCount;
    await t.pump(const Duration(milliseconds: 250));
    await t.pump(const Duration(milliseconds: 250));
    expect(game.sim!.stepCount, frozenStepCount);
    // 클리어된 런은 막힌-런 자동 복귀의 대상이 아니다 - 유예 시간(1.2s)을
    // 넘겨서까지 pump해도 run 모드 그대로여야 한다.
    await _pumpUntilEdit(t, game, maxPumps: 10);
    expect(game.mode, GameMode.run);
  });

  testWidgets('■을 탭하면 run 도중에도 edit 모드로 복귀하고 배치는 그대로, 선택은 해제된 채로 남는다',
      (t) async {
    final s = _trivialStage();
    final game = await _pumpGame(t, s);
    game.addPlacement(s.solution.single);
    await t.pump();

    await _tap(t, _runButtonCenter); // ▶ → run
    expect(game.mode, GameMode.run);
    // 아직 클리어 전 - 낙하에 필요한 시간(~0.84s)보다 훨씬 짧게(0.25s) 지남.
    expect(game.sim!.cleared, isFalse);

    await _tap(t, _runButtonCenter); // 같은 버튼, 이제 ■ → edit
    expect(game.mode, GameMode.edit);
    expect(game.sim, isNull);
    expect(game.placements.length, 1);
    expect(game.placements.single.type, PartType.rubberBall);
    expect(game.selectedIndex, isNull);
  });

  testWidgets('오버레이의 다음 버튼을 탭하면 onNextRequested가 호출된다 (화면 전환은 Task 11)',
      (t) async {
    final s = _trivialStage();
    final game = await _pumpGame(t, s);
    game.addPlacement(s.solution.single);
    await t.pump();

    var nextCalled = false;
    game.onNextRequested = () => nextCalled = true;

    await _tap(t, _runButtonCenter);
    await _pumpUntilCleared(t, game);
    expect(game.sim!.cleared, isTrue);

    await _tap(t, WinOverlay.nextButtonCenter);

    expect(nextCalled, isTrue);
  });

  testWidgets('오버레이의 다시 버튼을 탭하면 edit 모드로 복귀하고 오버레이가 사라지며 배치는 그대로 남는다',
      (t) async {
    final s = _trivialStage();
    final game = await _pumpGame(t, s);
    game.addPlacement(s.solution.single);
    await t.pump();

    await _tap(t, _runButtonCenter);
    await _pumpUntilCleared(t, game);
    expect(game.sim!.cleared, isTrue);

    await _tap(t, WinOverlay.retryButtonCenter);

    expect(game.mode, GameMode.edit);
    expect(game.sim, isNull);
    expect(game.camera.viewport.children.whereType<WinOverlay>(), isEmpty);
    expect(game.placements.length, 1);
    expect(game.placements.single.type, PartType.rubberBall);
  });

  testWidgets(
      '목표를 못 채운 채 동적 물체가 전부 화면 밖으로 사라지면 유예 시간 후 자동으로 edit 모드로 '
      '복귀하고 배치는 그대로 남는다 (첫 플레이테스트 재현: 아무것도 안 놓고 ▶만 누름)', (t) async {
    final s = _deadRunStage();
    final game = await _pumpGame(t, s);
    // 정적 부품 하나를 미리 놓아 둔다 - "동적 물체 0개"와 "배치 목록이
    // 원래부터 비어 있었다"를 구분해서, 되돌아온 뒤에도 배치가 실제로
    // 보존됐는지 의미 있게 검증한다. plank는 static이라 이 부품 자체는
    // 절대 destroy queue에 걸리지 않는다(sim_world.dart 카탈로그 참고).
    game.addPlacement(s.solution.single);
    await t.pump();

    await _tap(t, _runButtonCenter);
    expect(game.mode, GameMode.run);

    await _pumpUntilEdit(t, game);

    expect(game.mode, GameMode.edit,
        reason: '이 pump 예산 안에 자동 복귀하지 않음 - 유예 타이머 확인');
    expect(game.sim, isNull);
    expect(game.placements.length, 1);
    expect(game.placements.single.type, PartType.plank);
  });
}

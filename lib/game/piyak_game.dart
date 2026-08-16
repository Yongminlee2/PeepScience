import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:forge2d/forge2d.dart' hide World;

import '../services/sound.dart';
import '../sim/catalog.dart';
import '../sim/sim_world.dart';
import '../sim/stage_data.dart';
import 'hud.dart';
import 'input.dart';
import 'part_view.dart';

enum GameMode { edit, run }

/// Flame render layer. Two modes over the same scene data
/// (`stage.preset` ++ [placements]):
/// - edit: no [SimWorld] - parts are drawn statically at their authored
///   positions.
/// - run ([startRun]): a [SimWorld] drives the same parts; each gets a live
///   [PartView] that copies its body's position/angle every [update].
///   [resetToEdit] discards the SimWorld again; [placements] itself is
///   untouched by either call.
///
/// World is 16x9 meters, y-down, origin top-left - same directions as the
/// screen - so meters -> pixels is a straight `* ppm`, never a flip (see
/// PartView, which does the actual per-frame copy).
class PiyakGame extends FlameGame with DragCallbacks {
  PiyakGame(this.stage)
    : super(
        camera: CameraComponent.withFixedResolution(width: 1600, height: 900),
      );

  /// Meters -> pixels; single source of truth is [kPpm] in part_view.dart.
  static const double ppm = kPpm;

  final StageData stage;

  /// Player-placed parts (tray drag/drop lands here in a later task).
  /// Survives startRun()/resetToEdit() - only the physics (sim) is
  /// discarded on reset, never this list.
  final List<Placement> placements = [];

  GameMode mode = GameMode.edit;
  SimWorld? sim;

  /// Fired once per run, the frame `sim!.cleared` first becomes true (see
  /// `update`'s accumulator loop / `_onCleared`) - passed [stage]'s own id.
  /// Task 11 wires this to progress-tracking/navigation; here it's just
  /// invoked.
  void Function(String stageId, int stars)? onCleared;

  /// Fired when [WinOverlay]'s 다음(next) button is tapped. Task 11 wires
  /// this to advancing to the next stage; here it's just invoked.
  VoidCallback? onNextRequested;

  /// Predict-before-running choice for experiment stages. It deliberately
  /// survives retry so the child can change their mind instead of being
  /// forced through the prompt from scratch after every attempt.
  PartType? predictionChoice;

  /// Result of the latest successful run, rendered by [WinOverlay] and
  /// persisted by GameScreen through [onCleared].
  int earnedStars = 0;

  double runElapsedSeconds = 0;
  bool _starPickupCelebrated = false;

  /// Index into [placements] currently selected in edit mode (draws a
  /// selection ring + delete-X, and a rotate handle when the type is
  /// rotatable - see input.dart's SelectionOverlay), or null if nothing is
  /// selected. Tap/drag handling lives in input.dart's handleEdit*()
  /// functions; cleared whenever [startRun] is called.
  int? selectedIndex;

  /// Index into [placements] whose rotate handle is mid-drag, or null.
  /// Owned by input.dart's handleEditDrag*() functions.
  int? rotatingIndex;

  /// Angle (degrees) to fall back to if a rotate drag ends on an invalid
  /// (overlapping) angle - see input.dart's handleEditDragEnd. Meaningless
  /// while [rotatingIndex] is null.
  double rotateFallbackAngleDeg = 0;

  /// Running canvas-space pointer position for the rotate drag in progress,
  /// or null. Owned by input.dart's handleEditDrag*() functions - see
  /// handleEditDragUpdate's doc comment for why this is tracked
  /// incrementally instead of read straight off each DragUpdateEvent.
  Vector2? rotateDragCanvasPos;

  /// Index into [placements] currently being drag-moved (grabbed by its own
  /// footprint and following the finger), or null. Owned by input.dart's
  /// handleEditMoveDrag*() functions - mirrors [rotatingIndex]'s role for
  /// rotation.
  int? movingIndex;

  /// World-space offset (meters, grab point minus the placement's center) at
  /// the moment [movingIndex] was grabbed - preserved through the drag so
  /// the part follows the finger without its center jumping to the pointer.
  /// Meaningless while [movingIndex] is null.
  Vector2 moveGrabOffsetM = Vector2.zero();

  /// Placement center (meters) to revert to if the move drag ends somewhere
  /// illegal - captured once at grab time and never updated mid-drag, so a
  /// revert always lands back where the part truly started no matter how
  /// far it wandered live. Meaningless while [movingIndex] is null.
  Vector2 movePreDragPosM = Vector2.zero();

  /// Running canvas-space pointer position for the move drag in progress, or
  /// null. Same canvasDelta-accumulation reasoning as [rotateDragCanvasPos]
  /// (see input.dart's handleEditDragUpdate doc comment).
  Vector2? moveDragCanvasPos;

  /// Pointer id that grabbed [movingIndex], or null. Recorded at grab time
  /// (handleEditMoveDragStart) so a SECOND pointer's own onDragUpdate/
  /// onDragEnd - piyak_game.dart routes every pointer's events through the
  /// same shared handleEditMoveDrag*() functions, there's no per-component
  /// dispatch for this - can never be mistaken for the pointer actually
  /// driving the move. The sibling half of this same problem is guarded at
  /// grab time too: handleEditMoveDragStart refuses to claim
  /// [movingIndex] while it's already non-null, so only ONE pointer can ever
  /// own a move at a time in the first place.
  int? movingPointerId;

  final List<PartView> _views = [];
  double _acc = 0;

  // Task 18: 사운드 트리거 배선 - sim_world.dart는 순수 Dart로 남기고,
  // 여기서 매 프레임 관찰 가능한 상태(카운터/래치)를 이전 값과 비교해
  // 변화(=사건)를 감지한다(브리핑의 "sim에 이벤트 훅이 없으면 game
  // 레이어에서 상태를 폴링" 지침). 전부 startRun()에서 새 sim에 맞춰
  // 리셋된다.
  int _lastPopped = 0;
  int _lastBounce = 0;
  bool _lastButtonPressed = false;
  double _gearTickAccum = 0;
  bool _hasMotorGear = false;
  static const double _gearTickInterval = 0.5;

  // 막힌 런 자동 복귀 - 첫 플레이테스트에서 실기기로 확인된 문제: 목표
  // 미달성 상태로 동적 물체가 전부 destroy queue(sim_world.dart step()의
  // 화면밖 소거)에 쓸려 나가면, update()의 !s.cleared 게이트는 계속 돌지만
  // 화면엔 아무 변화가 없어 "고장났다"로 읽힌다(스테이지1에서 아무것도
  // 안 놓고 ▶만 눌렀을 때 공이 1초 안에 사라지는 게 실제 1호 반응). 이
  // 상태가 [_deadRunGrace]초 유지되면 자동으로 resetToEdit() - null이면
  // 카운트 중이 아님, startRun()마다 리셋.
  double? _deadRunTimer;
  static const double _deadRunGrace = 1.2;

  @override
  Future<void> onLoad() async {
    // Default viewfinder centers world (0,0) in the viewport; our world's
    // origin is top-left, so pin the anchor there instead (position stays
    // (0,0) - the default).
    camera.viewfinder.anchor = Anchor.topLeft;
    // Added once, before any PartView - priority keeps it behind every part
    // regardless of insertion order, and it's never touched by
    // _rebuildViews() (background never changes across edit/run/placements).
    world.add(_BackgroundView(stage.world));
    _rebuildViews();
    // Edit-mode-only selection ring/handle/delete-X for the currently
    // selected placement (input.dart) - high priority keeps it drawn on top
    // of every PartView regardless of _rebuildViews()'s add/remove churn.
    world.add(SelectionOverlay(this));
    // Screen-space HUD (viewport, not world) - see hud.dart's own doc
    // comment for why it has to be mounted there.
    camera.viewport.add(TrayBar(this));
    camera.viewport.add(GoalBadge(this));
    if (stage.feature == StageFeature.chainReaction) {
      camera.viewport.add(ChainReactionRibbon(this));
    }
    // 부품 제한(2번째 별 조건)은 예측 패널이 있어도 항상 보여야 실행 전에
    // 채점 기준을 확인할 수 있다 - ChallengeRibbon이 스스로 겹치지 않는
    // 자리를 고른다(hud.dart의 _positionFor 참고).
    if (stage.challenge != null) {
      camera.viewport.add(ChallengeRibbon(this));
    }
    if (stage.prediction != null) {
      camera.viewport.add(PredictionPanel(this));
    }
    camera.viewport.add(RunToggleButton(this));
    // 목표물 강조 펄스(스킨 패스: 목표 배지가 뭘 가리키는지 안 읽힌다는
    // 오너 피드백) - 최초 진입 1회. resetToEdit()도 같은 호출을 하므로
    // 다시/■/막힌 런 자동복귀 중 어디로 돌아와도 매번 다시 보여준다.
    triggerGoalPulse();
  }

  @override
  Color backgroundColor() => switch (stage.world) {
    // Fixed 16:9 gameplay is letterboxed on modern 19.5:9/20:9 phones.
    // Match the bars to each world instead of exposing the old bright
    // cyan debug-looking frame around every scene.
    1 => const Color(0xFFE9E2D8),
    2 => const Color(0xFFD8E4D1),
    3 => const Color(0xFFD8D2CC),
    4 => const Color(0xFF18244A),
    _ => const Color(0xFFFFFBF0),
  };

  void startRun() {
    // Stale overlay/confetti from a previous run, if any (normally already
    // gone via the 다시/다음 buttons - see _removeWinOverlay's own doc
    // comment for why this call is here defensively too).
    _removeWinOverlay();
    sim = SimWorld(stage, placements);
    mode = GameMode.run;
    // Run mode has no selection/edit affordances (shared-contract Task 8).
    selectedIndex = null;
    rotatingIndex = null;
    movingIndex = null;
    // Fresh sim -> fresh step accumulator too: leftover _acc from the run
    // just discarded (e.g. capped at 0.25 the frame it cleared) would
    // otherwise fast-forward this new sim several steps on its very first
    // update() - visible as a stutter/skip right after tapping 다시.
    _acc = 0;
    // Fresh sim -> fresh sound-trigger bookkeeping (see the fields' own doc
    // comment above). motorGear presence can't change mid-run (the part is
    // pinned in place by its own revolute joint - see sim_world.dart's
    // _buildCatalogBody - so it can never trigger the off-screen destroy
    // queue), so this is safe to compute once here instead of every frame.
    _lastPopped = 0;
    _lastBounce = 0;
    _lastButtonPressed = false;
    _gearTickAccum = 0;
    _deadRunTimer = null;
    runElapsedSeconds = 0;
    earnedStars = 0;
    _starPickupCelebrated = false;
    _hasMotorGear = sim!.world.bodies.any(
      (b) => (b.userData as PartTag?)?.part == PartType.motorGear,
    );
    _rebuildViews();
  }

  void resetToEdit() {
    _removeWinOverlay();
    sim = null;
    mode = GameMode.edit;
    _rebuildViews();
    triggerGoalPulse();
  }

  void selectPrediction(PartType type) {
    if (mode != GameMode.edit || stage.prediction == null) return;
    if (type != PartType.rubberBall && type != PartType.metalBall) return;
    predictionChoice = type;
    Sound.play(Sfx.tap);
  }

  bool get canStartRun => stage.prediction == null || predictionChoice != null;

  void nudgePrediction() {
    for (final child in camera.viewport.children) {
      if (child is PredictionPanel) child.nudge();
    }
  }

  /// Replays the goal-object affordance pulse (see [PartView.pulse]'s own
  /// doc comment for the animation) on every PartView backing this stage's
  /// goal object(s) ([_goalTargetViews]). Edit-mode only - a run's
  /// SimWorld-backed PartViews are position/angle-synced from live bodies
  /// every frame regardless (PartView.update), and there is nothing to
  /// place mid-run anyway. Called once from [onLoad] (initial edit-mode
  /// entry), once from [resetToEdit] (다시/■/dead-run-auto-revert all funnel
  /// through that one choke point - see its own doc comment), and replayed
  /// on demand by a [GoalBadge] tap ([_dispatchTap]).
  void triggerGoalPulse() {
    if (mode != GameMode.edit) return;
    for (final v in _goalTargetViews()) {
      v.pulse();
    }
  }

  /// The PartView(s) backing this stage's goal object(s): the basket/button
  /// preset, or every PRESET balloon/domino (shared-contract.md: only
  /// fromPreset entries count toward popBalloons/toppleDominoes, so a
  /// tray-placed balloon/domino is never a pulse target either).
  /// `_views[i]` mirrors `stage.preset[i]` 1:1 for `i < stage.preset.length`
  /// - see [_sceneEntries]'s own doc comment for why.
  Iterable<PartView> _goalTargetViews() sync* {
    for (var i = 0; i < stage.preset.length; i++) {
      final p = stage.preset[i];
      final isTarget = switch (stage.goal.type) {
        GoalType.ballInBasket => p.type == 'basket',
        GoalType.pressButton => p.type == 'button',
        GoalType.popBalloons => p.type == 'balloon',
        GoalType.toppleDominoes => p.type == 'domino',
      };
      if (isTarget) yield _views[i];
    }
  }

  /// Test helper: the scale factor of the first goal-target PartView (see
  /// [_goalTargetViews]), or null if this stage's goal has no matching
  /// preset object yet mounted. Mirrors [ballY]'s role.
  double? goalPulseScale() {
    final views = _goalTargetViews().toList();
    return views.isEmpty ? null : views.first.scale.x;
  }

  /// Removes any [WinOverlay] mounted under the viewport - a no-op when
  /// none is showing. The single choke point for tearing the overlay (and,
  /// cascading, its confetti/text/button children - see WinOverlay's own
  /// doc comment) down; both mode-transition entry points above call it
  /// unconditionally so it can never linger into edit mode or a fresh run
  /// regardless of which one a caller (today: RunToggleButton's 다시 tap;
  /// later, Task 11's navigation) takes.
  void _removeWinOverlay() {
    camera.viewport.removeWhere((c) => c is WinOverlay);
  }

  /// Adds a player-placed part and immediately refreshes the render layer -
  /// the tray drag-input layer (lib/game/hud.dart) is the only caller today,
  /// via `canPlaceAt`/`resolveDrop` in lib/game/input.dart deciding whether
  /// and where. Task 8/12 will add more mutators (move/delete) alongside
  /// this one; they should follow the same call-_rebuildViews()-immediately
  /// pattern so `placements` and the rendered scene never drift apart.
  void addPlacement(Placement p) {
    placements.add(p);
    _rebuildViews();
  }

  /// Removes the placement at [index] and refreshes the render layer -
  /// mirrors [addPlacement]. Task 8's delete-X button is the only caller
  /// today.
  ///
  /// Also adjusts [selectedIndex]/[rotatingIndex] for the shift this causes
  /// in every later index: null them out if either pointed at the removed
  /// placement itself, decrement if either pointed past it - this is the
  /// single choke point for that bookkeeping (callers don't also need to
  /// touch these fields). Matters even outside multi-touch: without it, a
  /// second finger deleting a different-from-rotating placement while the
  /// first finger is still mid-rotate-drag leaves [rotatingIndex] pointing
  /// at whatever placement happens to have shifted into its old slot, and
  /// the next onDragUpdate silently rewrites THAT placement's angle.
  void removePlacement(int index) {
    assert(index >= 0 && index < placements.length);
    placements.removeAt(index);
    selectedIndex = _shiftIndexAfterRemoval(selectedIndex, index);
    rotatingIndex = _shiftIndexAfterRemoval(rotatingIndex, index);
    movingIndex = _shiftIndexAfterRemoval(movingIndex, index);
    _rebuildViews();
  }

  static int? _shiftIndexAfterRemoval(int? idx, int removedIndex) {
    if (idx == null || idx == removedIndex) return null;
    return idx > removedIndex ? idx - 1 : idx;
  }

  /// Replaces the placement at [index] with the same type/position but a
  /// new [angleDeg] - mirrors [addPlacement]. [Placement] has final fields,
  /// so this replaces the list entry rather than mutating it in place.
  /// Task 8's rotate handle is the only caller today.
  void setPlacementAngle(int index, double angleDeg) {
    assert(index >= 0 && index < placements.length);
    final p = placements[index];
    placements[index] = Placement(
      type: p.type,
      x: p.x,
      y: p.y,
      angleDeg: angleDeg,
    );
    _rebuildViews();
  }

  /// Replaces the placement at [index] with the same type/angle but a new
  /// (x,y) - mirrors [setPlacementAngle]. Drag-to-move (input.dart's
  /// handleEditMoveDrag*()) is the only caller today.
  void setPlacementPosition(int index, double x, double y) {
    assert(index >= 0 && index < placements.length);
    final p = placements[index];
    placements[index] = Placement(
      type: p.type,
      x: x,
      y: y,
      angleDeg: p.angleDeg,
    );
    _rebuildViews();
  }

  // Edit-mode select/rotate/delete input. DragCallbacks must be mixed onto
  // this class itself to receive events (FlameGame _is_ a Component - see
  // flame's DragCallbacks doc comment) - but all the actual hit-testing/
  // geometry lives in input.dart's handleEdit*() functions, consistent with
  // how canPlaceAt/resolveDrop already take a PiyakGame rather than living
  // as methods on it.
  //
  // ---------------------------------------------------------------------
  // Real-finger tap synthesis - DO NOT delete this as "redundant", and do
  // not add TapCallbacks back anywhere in this game (here, or on
  // RunToggleButton/WinOverlayButton in hud.dart).
  //
  // Root cause (device-verified): this game also needs real drags (tray
  // placement, rotate handle), so flame always has a
  // MultiDragScaleGestureRecognizer registered. Whenever ANY TapCallbacks
  // exists anywhere in the game too, flame ALSO registers a
  // MultiTapGestureRecognizer, and the two compete in one Flutter gesture
  // arena per pointer - but this game never enables flame's scale gesture,
  // so the drag recognizer resolves itself ACCEPTED on the very first
  // PointerMoveEvent it sees, zero slop (verified against the installed
  // flame 1.38.0 source: multi_drag_scale_recognizer.dart's
  // _DragPointerState._move, the `!recognizer.hasScale` branch). Once it
  // accepts, the arena rejects every other recognizer for that pointer, so
  // a TapCallbacks component's onTapUp silently becomes onTapCancel
  // instead - no exception, nothing to catch. A real finger essentially
  // always drifts a few px between touch-down and lift-off, so on a real
  // device this used to fire on EVERY tap, not just accidental swipes:
  // confirmed with `adb shell input swipe x y x+6 y+3 80` (6px drift,
  // 80ms) killing every tap, while `adb shell input tap` (zero movement) -
  // and every widget-test tester.tapAt/dragFrom(..., touchSlopX: 0,
  // touchSlopY: 0), also zero movement - looked fine. See
  // test/game/real_touch_test.dart for gestures that actually drift, the
  // way the other test files' zero-movement gestures never did.
  //
  // Fix: this game has no TapCallbacks at all anymore. Every tap (part
  // select, delete-X, deselect, the run toggle, the win-overlay buttons) is
  // instead synthesized below from the one gesture flame can still resolve
  // reliably regardless of finger drift: a drag. onDragEnd treats a
  // short/fast drag - and ONLY a drag not already claimed by a real
  // interaction (tray placement is a different component's gesture
  // entirely, see input.dart's Task 8 header comment for why that never
  // reaches here; a rotate-handle/ring-band grab or a placement move-grab is
  // guarded via `consumed` below) - as a tap at its START position. This
  // also covers the zero-movement
  // case (existing tests, `adb shell input tap`): with no competing tap
  // recognizer left, flame's arena awards the drag recognizer that pointer
  // immediately (it's the only member), so onDragStart+onDragEnd still
  // fire even for zero movement - just with `traveled` staying 0.
  //
  // _tapCandidates tracks the in-flight state per pointer id (multi-touch
  // safe - see removePlacement's own doc comment for why this game already
  // has to think in per-pointer terms elsewhere). _dispatchTap resolves a
  // confirmed tap to exactly one action, in the same priority order
  // flame's TapCallbacks z-order used to give for free.
  // Public (no leading underscore) - handleEditMoveDragEnd (input.dart)
  // reuses this exact threshold to decide whether a footprint grab ever
  // left "tap" territory before treating it as a real move (see that
  // function's own doc comment for why: a zero/near-zero-movement grab must
  // never re-snap a gear against a different neighbor than the one it was
  // already meshed with).
  static const double kTapMaxTravelPx = 15;
  static const Duration _kTapMaxDuration = Duration(milliseconds: 300);

  final Map<int, _TapCandidate> _tapCandidates = {};

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final rotatingBefore = rotatingIndex;
    handleEditDragStart(this, event);
    // Ladder step 2 (move-grab) only gets a turn if step 1 (rotate) declined
    // - see input.dart's drag-start priority ladder comment.
    final movingBefore = movingIndex;
    if (rotatingIndex == null) {
      handleEditMoveDragStart(this, event);
    }
    _tapCandidates[event.pointerId] = _TapCandidate(
      start: event.canvasPosition,
      // This exact call just claimed the rotate handle OR a placement's
      // footprint (null -> non-null, either field)? Then this pointer is a
      // real interaction from frame one, never a tap, no matter how little
      // it then moves. Comparing against movingBefore (captured right
      // before this call), not a bare `movingIndex != null` read, matters
      // now that handleEditMoveDragStart can decline because ANOTHER
      // pointer already owns movingIndex (a second pointer touching some
      // OTHER part's footprint while a move is in flight) - a bare read
      // would wrongly mark THIS pointer consumed for someone else's move.
      consumed:
          (rotatingBefore == null && rotatingIndex != null) ||
          (movingBefore == null && movingIndex != null),
    );
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    handleEditDragUpdate(this, event);
    handleEditMoveDragUpdate(this, event);
    _tapCandidates[event.pointerId]?.traveled += event.canvasDelta.length;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    handleEditDragEnd(this, event);
    // Removed (not just read) before handleEditMoveDragEnd so its own
    // release-time no-move short-circuit (input.dart) can see exactly how
    // far THIS pointer travelled - the same number _dispatchTap's own tap
    // check below uses, so "was this a tap" means the same thing in both
    // places (Important 2/Minor 3 fix).
    final tap = _tapCandidates.remove(event.pointerId);
    handleEditMoveDragEnd(this, event, traveled: tap?.traveled ?? 0);
    if (tap != null &&
        !tap.consumed &&
        tap.traveled < kTapMaxTravelPx &&
        DateTime.now().difference(tap.startTime) < _kTapMaxDuration) {
      _dispatchTap(tap.start);
    }
  }

  /// Resolves a confirmed tap at [canvasPos] to exactly one action, in the
  /// same priority order flame's TapCallbacks z-order used to give for free
  /// (win-overlay buttons on top, then the run toggle, then the goal badge,
  /// then in-field select/delete/deselect) - see this class's "Real-finger
  /// tap synthesis" comment above for the full mechanism.
  ///
  /// Uses componentsAtPoint (walking the real component tree top-down,
  /// applying each ancestor's actual transform: camera -> viewport -> ...)
  /// rather than PositionComponent.containsPoint/absoluteToLocal on a
  /// specific button - the latter climbs from the component UPWARD and
  /// silently stops (wrong answer, not an error) at the first
  /// non-PositionComponent ancestor, and both CameraComponent and Viewport
  /// are exactly that, so every HUD component here would be affected.
  /// componentsAtPoint already yields topmost-first, so WinOverlayButton
  /// (priority 100, via WinOverlay) naturally comes before RunToggleButton
  /// and GoalBadge (both priority 0, and spatially disjoint - bottom-right
  /// vs. top-left - so their relative order never matters) without any
  /// hand-coded z-order.
  void _dispatchTap(Vector2 canvasPos) {
    for (final c in componentsAtPoint(canvasPos)) {
      if (c is WinOverlayButton) {
        c.onTap();
        return;
      }
      if (c is RunToggleButton) {
        c.activate();
        return;
      }
      if (c is PredictionChoiceButton) {
        c.activate();
        return;
      }
      if (c is GoalBadge) {
        c.activate();
        return;
      }
    }
    handleEditTapUp(this, canvasPos);
  }

  @override
  void update(double dt) {
    final s = sim;
    // !s.cleared here is what makes the freeze permanent: once cleared
    // flips true (inside the loop below), this whole branch is skipped on
    // every later frame for the rest of this sim's lifetime - cleared only
    // ever resets by a fresh startRun() replacing `sim` entirely.
    if (mode == GameMode.run && s != null && !s.cleared) {
      runElapsedSeconds += dt;
      _acc += dt;
      _acc = min(_acc, 0.25);
      while (_acc >= SimWorld.dt) {
        s.step();
        _acc -= SimWorld.dt;
        _handleStarPickup(s);
        if (s.cleared) {
          // Stop stepping THIS frame too, not just future ones - a stage
          // that clears on e.g. the 3rd of up to 15 steps queued in one
          // frame (the 0.25s accumulator cap / SimWorld.dt =~ 15) must not
          // silently run the other 12 anyway before anyone finds out.
          _onCleared();
          break;
        }
      }
      // Once per Flame frame (not per physics step) is enough: a "did this
      // counter move at all since last frame" check still catches every
      // event even when the loop above ran several steps to catch up, and
      // playing at most one pop/boing/buttonClick per frame avoids a burst
      // of overlapping sounds on a hitch.
      _pollSimSounds(s);
      _tickGearSound(dt);
      _tickDeadRunTimer(s, dt);
    }
    super.update(dt); // cascades into PartView.update -> body sync
  }

  // 풍선 펑/트램펄린 반발/버튼 눌림 - sim_world.dart의 순수 카운터·래치를
  // 이전 프레임 값과 비교해 변화를 감지한다(sim 쪽에 콜백을 두지 않고 game
  // 레이어에서 폴링 - 브리핑 지침). 델타 값만큼이 아니라 "움직였으면 1번"만
  // 재생해 한 프레임에 여러 개가 겹쳐 몰리는 걸 피한다.
  void _pollSimSounds(SimWorld s) {
    if (s.poppedCount > _lastPopped) Sound.play(Sfx.pop);
    _lastPopped = s.poppedCount;
    if (s.bounceCount > _lastBounce) Sound.play(Sfx.boing);
    _lastBounce = s.bounceCount;
    if (s.buttonPressed && !_lastButtonPressed) Sound.play(Sfx.buttonClick);
    _lastButtonPressed = s.buttonPressed;
  }

  // 톱니 회전 중 주기적 gearTick - 모터 톱니가 있는 동안 0.5초마다 한 번
  // (스팸 방지). 모터 톱니 유무는 startRun()에서 한 번만 계산해 둔
  // _hasMotorGear를 쓴다(런 중에는 안 바뀜 - 그 필드 자신의 doc comment
  // 참고).
  void _tickGearSound(double dt) {
    if (!_hasMotorGear) return;
    // Same clamp idea as _acc above: without it, a huge dt spike (app
    // backgrounded/resumed) would bank a large backlog and then fire a
    // rapid-fire burst of catch-up ticks across the next several frames
    // instead of just one.
    _gearTickAccum = min(_gearTickAccum + dt, _gearTickInterval);
    if (_gearTickAccum >= _gearTickInterval) {
      _gearTickAccum = 0;
      Sound.play(Sfx.gearTick);
    }
  }

  // 막힌 런 자동 복귀 타이머 - 동적 물체(BodyType.dynamic; platform/basket/
  // button과 plank/fan/trampoline/tack 같은 정적 카탈로그 부품은 애초에
  // dynamic이 아니라 여기 안 잡힘 - catalog.dart의 density==null이 static)
  // 가 하나라도 world에 남아 있으면 즉시 카운트를 지운다: 아직 화면에 뭔가
  // 보이고(예: 못 맞힌 공이 바닥에 멈춤) 원인을 읽을 수 있는 상태는 범위
  // 밖 - 조용히 멈춘 화면만 고친다. cleared는 update()의 바깥 !s.cleared
  // 게이트로 대부분 걸러지지만, 이 프레임의 스텝 루프 도중 막 cleared가
  // 된 경우까지 한 번 더 방어.
  void _tickDeadRunTimer(SimWorld s, double dt) {
    final hasDynamicBody = s.world.bodies.any(
      (b) => b.bodyType == BodyType.dynamic,
    );
    if (s.cleared || hasDynamicBody) {
      _deadRunTimer = null;
      return;
    }
    final elapsed = (_deadRunTimer ?? 0) + dt;
    if (elapsed < _deadRunGrace) {
      _deadRunTimer = elapsed;
      return;
    }
    _deadRunTimer = null;
    // tap: 삭제(입력 취소)와 같은 소리 - "이번 시도 무효, 되돌림"이라는
    // 결이 같다(input.dart의 삭제=tap과 동일 판단). boing은 이미
    // 트램펄린 반발 전용 트리거라 여기서 재사용하면 트램펄린이 없는
    // 스테이지에서 튀는 소리가 나 오해를 준다.
    Sound.play(Sfx.tap);
    resetToEdit();
  }

  // Called exactly once per run: `s.cleared` starts false and latches
  // permanently true (SimWorld's own contract), and this is the only call
  // site, reached only from the `if (s.cleared)` transition-check above -
  // which update()'s own `!s.cleared` guard (see its comment) stops from
  // ever running again for the same `sim`. So the false->true transition
  // this reacts to can only be observed, and thus only fire this, once.
  void _onCleared() {
    Sound.play(Sfx.win);
    final challenge = stage.challenge;
    final partStar =
        challenge == null || placements.length <= challenge.partLimit;
    final bonusStar = challenge?.collectibleStar != null
        ? (sim?.starCollected ?? false)
        : stage.prediction != null
        ? predictionChoice == stage.prediction!.answer
        : true;
    earnedStars = 1 + (partStar ? 1 : 0) + (bonusStar ? 1 : 0);
    onCleared?.call(stage.id, earnedStars);
    camera.viewport.add(WinOverlay(this));
  }

  void _handleStarPickup(SimWorld s) {
    if (!s.starCollected || _starPickupCelebrated) return;
    _starPickupCelebrated = true;
    final star = stage.challenge?.collectibleStar;
    if (star == null) return;
    Sound.play(Sfx.buttonClick);
    world.add(starPickupBurst(Vector2(star.x, star.y) * kPpm));
  }

  /// Test helper: first ball's world-space y in meters (run mode only).
  double ballY() {
    final s = sim;
    if (s == null) return 0;
    return s.world.bodies
        .firstWhere((b) {
          final t = b.userData;
          return t is PartTag &&
              (t.part == PartType.rubberBall || t.part == PartType.metalBall);
        })
        .position
        .y;
  }

  // Rebuilds every scene PartView from scratch: simplest way to keep the
  // visuals in sync with whichever data source is current (authored
  // positions in edit mode, live bodies in run mode) without tracking
  // per-part diff/add/remove state across mode switches.
  void _rebuildViews() {
    for (final v in _views) {
      v.removeFromParent();
    }
    _views.clear();
    // SimWorld._build() creates exactly one PartTag-tagged body per
    // stage.preset/placements entry, in that same order (gear/seesaw pins
    // are extra untagged anchor bodies, filtered out here) - see
    // sim_world.dart's _build/_buildCatalogBody.
    final bodies = sim == null
        ? const <Body>[]
        : sim!.world.bodies.where((b) => b.userData is PartTag).toList();
    final entries = _sceneEntries();
    // SimWorld._build() must create exactly one PartTag body per
    // preset/placement entry, in that same order (see the comment above) -
    // this was previously only a documented assumption; placements now
    // change at runtime (lib/game/hud.dart's tray drag), so a silent
    // mis-pairing here would show the wrong body under the wrong part.
    // Fail loudly instead.
    assert(
      sim == null || bodies.length == entries.length,
      '_rebuildViews: expected ${entries.length} tagged bodies for '
      '${entries.length} scene entries, got ${bodies.length}',
    );
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final view = PartView(
        part: e.part,
        preset: e.preset,
        platformWidthM: e.platformWidthM,
        posM: Vector2(e.xM, e.yM),
        angleRad: e.angleDeg * pi / 180,
        body: i < bodies.length ? bodies[i] : null,
      );
      world.add(view);
      _views.add(view);
    }
  }

  List<_SceneEntry> _sceneEntries() {
    final list = <_SceneEntry>[];
    for (final p in stage.preset) {
      if (p.type == 'platform' || p.type == 'basket' || p.type == 'button') {
        list.add(
          _SceneEntry(
            preset: p.type,
            xM: p.x,
            yM: p.y,
            angleDeg: p.angleDeg,
            platformWidthM: p.w ?? 0,
          ),
        );
      } else {
        list.add(
          _SceneEntry(
            part: partTypeFromJson(p.type),
            xM: p.x,
            yM: p.y,
            angleDeg: p.angleDeg,
          ),
        );
      }
    }
    final collectibleStar = stage.challenge?.collectibleStar;
    if (collectibleStar != null) {
      list.add(
        _SceneEntry(
          preset: 'collectible_star',
          xM: collectibleStar.x,
          yM: collectibleStar.y,
          angleDeg: 0,
        ),
      );
    }
    for (final pl in placements) {
      list.add(
        _SceneEntry(part: pl.type, xM: pl.x, yM: pl.y, angleDeg: pl.angleDeg),
      );
    }
    return list;
  }
}

/// One in-flight tap candidate for [PiyakGame._tapCandidates] - see that
/// field's own doc comment ("Real-finger tap synthesis", above
/// [PiyakGame.onDragStart]) for what this is for.
class _TapCandidate {
  _TapCandidate({required this.start, required this.consumed})
    : startTime = DateTime.now();

  /// Canvas position the drag started at - a confirmed tap fires here, not
  /// wherever the pointer happened to drift to by release.
  final Vector2 start;

  final DateTime startTime;

  /// True if this pointer was claimed by a real interaction (today: the
  /// rotate handle/ring band, or a placement move-grab) the moment it
  /// started - if so, never a tap, regardless of how little it then moves
  /// or how quickly it ends.
  final bool consumed;

  /// Total path length (sum of |canvasDelta| across every onDragUpdate),
  /// not net displacement - a wobble that returns near its start still
  /// accumulates real travel here.
  double traveled = 0;
}

class _SceneEntry {
  const _SceneEntry({
    this.part,
    this.preset = '',
    required this.xM,
    required this.yM,
    required this.angleDeg,
    this.platformWidthM = 0,
  });

  final PartType? part;
  final String preset;
  final double xM, yM, angleDeg;
  final double platformWidthM;
}

/// World-themed backdrop, cover-fit behind every [PartView]. If
/// `assets/images/bg/world<N>.png` isn't in the asset bundle (true for every
/// world today - no art exists yet), renders nothing and [backgroundColor]'s
/// flat color shows through unchanged, so the game looks exactly as before.
class _BackgroundView extends PositionComponent {
  _BackgroundView(this.worldNum)
    : super(priority: -1000, size: Vector2(1600, 900));

  final int worldNum;
  Sprite? _sprite;

  @override
  Future<void> onLoad() async {
    final relPath = 'bg/world$worldNum.png';
    final manifest = await loadAssetManifestPaths();
    if (!manifest.contains('assets/images/$relPath')) return;
    _sprite = await Sprite.load(relPath);
  }

  @override
  void render(Canvas canvas) {
    final sprite = _sprite;
    if (sprite == null) return;
    // Cover-fit: scale so the image fills 1600x900 with no gap, cropping
    // whichever axis overflows (matches CSS background-size: cover).
    final src = sprite.originalSize;
    final scale = max(1600 / src.x, 900 / src.y);
    final rect = Rect.fromCenter(
      center: const Offset(800, 450),
      width: src.x * scale,
      height: src.y * scale,
    );
    sprite.renderRect(canvas, rect);
  }
}

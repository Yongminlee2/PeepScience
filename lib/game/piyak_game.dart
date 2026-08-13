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
class PiyakGame extends FlameGame with TapCallbacks, DragCallbacks {
  PiyakGame(this.stage)
      : super(
          camera: CameraComponent.withFixedResolution(
            width: 1600,
            height: 900,
          ),
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
  void Function(String stageId)? onCleared;

  /// Fired when [WinOverlay]'s 다음(next) button is tapped. Task 11 wires
  /// this to advancing to the next stage; here it's just invoked.
  VoidCallback? onNextRequested;

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
    camera.viewport.add(RunToggleButton(this));
  }

  @override
  Color backgroundColor() => const Color(0xFFBEE7F5);

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
    _hasMotorGear = sim!.world.bodies
        .any((b) => (b.userData as PartTag?)?.part == PartType.motorGear);
    _rebuildViews();
  }

  void resetToEdit() {
    _removeWinOverlay();
    sim = null;
    mode = GameMode.edit;
    _rebuildViews();
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
    placements[index] =
        Placement(type: p.type, x: p.x, y: p.y, angleDeg: angleDeg);
    _rebuildViews();
  }

  // Edit-mode select/rotate/delete input. TapCallbacks/DragCallbacks must be
  // mixed onto this class itself to receive events (FlameGame _is_ a
  // Component - see flame's TapCallbacks doc comment) - but all the actual
  // hit-testing/geometry lives in input.dart's handleEdit*() functions,
  // consistent with how canPlaceAt/resolveDrop already take a PiyakGame
  // rather than living as methods on it.
  @override
  void onTapUp(TapUpEvent event) => handleEditTapUp(this, event);

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    handleEditDragStart(this, event);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    handleEditDragUpdate(this, event);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    handleEditDragEnd(this, event);
  }

  @override
  void update(double dt) {
    final s = sim;
    // !s.cleared here is what makes the freeze permanent: once cleared
    // flips true (inside the loop below), this whole branch is skipped on
    // every later frame for the rest of this sim's lifetime - cleared only
    // ever resets by a fresh startRun() replacing `sim` entirely.
    if (mode == GameMode.run && s != null && !s.cleared) {
      _acc += dt;
      _acc = min(_acc, 0.25);
      while (_acc >= SimWorld.dt) {
        s.step();
        _acc -= SimWorld.dt;
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
    final hasDynamicBody =
        s.world.bodies.any((b) => b.bodyType == BodyType.dynamic);
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
    onCleared?.call(stage.id);
    camera.viewport.add(WinOverlay(this));
  }

  /// Test helper: first ball's world-space y in meters (run mode only).
  double ballY() {
    final s = sim;
    if (s == null) return 0;
    return s.world.bodies.firstWhere((b) {
      final t = b.userData;
      return t is PartTag &&
          (t.part == PartType.rubberBall || t.part == PartType.metalBall);
    }).position.y;
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
        list.add(_SceneEntry(
          preset: p.type,
          xM: p.x,
          yM: p.y,
          angleDeg: p.angleDeg,
          platformWidthM: p.w ?? 0,
        ));
      } else {
        list.add(_SceneEntry(
          part: partTypeFromJson(p.type),
          xM: p.x,
          yM: p.y,
          angleDeg: p.angleDeg,
        ));
      }
    }
    for (final pl in placements) {
      list.add(_SceneEntry(
        part: pl.type,
        xM: pl.x,
        yM: pl.y,
        angleDeg: pl.angleDeg,
      ));
    }
    return list;
  }
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

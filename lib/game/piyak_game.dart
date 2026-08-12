import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:forge2d/forge2d.dart' hide World;

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
    }
    super.update(dt); // cascades into PartView.update -> body sync
  }

  // Called exactly once per run: `s.cleared` starts false and latches
  // permanently true (SimWorld's own contract), and this is the only call
  // site, reached only from the `if (s.cleared)` transition-check above -
  // which update()'s own `!s.cleared` guard (see its comment) stops from
  // ever running again for the same `sim`. So the false->true transition
  // this reacts to can only be observed, and thus only fire this, once.
  void _onCleared() {
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

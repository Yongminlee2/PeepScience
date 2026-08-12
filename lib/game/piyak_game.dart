import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:forge2d/forge2d.dart' hide World;

import '../sim/catalog.dart';
import '../sim/sim_world.dart';
import '../sim/stage_data.dart';
import 'hud.dart';
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
class PiyakGame extends FlameGame {
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

  final List<PartView> _views = [];
  double _acc = 0;

  @override
  Future<void> onLoad() async {
    // Default viewfinder centers world (0,0) in the viewport; our world's
    // origin is top-left, so pin the anchor there instead (position stays
    // (0,0) - the default).
    camera.viewfinder.anchor = Anchor.topLeft;
    _rebuildViews();
    // Screen-space HUD (viewport, not world) - see hud.dart's own doc
    // comment for why it has to be mounted there.
    camera.viewport.add(TrayBar(this));
  }

  @override
  Color backgroundColor() => const Color(0xFFBEE7F5);

  void startRun() {
    sim = SimWorld(stage, placements);
    mode = GameMode.run;
    _rebuildViews();
  }

  void resetToEdit() {
    sim = null;
    mode = GameMode.edit;
    _rebuildViews();
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

  @override
  void update(double dt) {
    final s = sim;
    if (mode == GameMode.run && s != null) {
      _acc += dt;
      _acc = min(_acc, 0.25);
      while (_acc >= SimWorld.dt) {
        s.step();
        _acc -= SimWorld.dt;
      }
    }
    super.update(dt); // cascades into PartView.update -> body sync
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

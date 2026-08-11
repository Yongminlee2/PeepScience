import 'dart:math';

import 'package:forge2d/forge2d.dart';

import 'catalog.dart';
import 'stage_data.dart';

/// Tag attached to every forge2d [Body]'s userData so later layers (render,
/// goal-counting) can identify what a body represents.
class PartTag {
  const PartTag({this.part, this.preset = '', this.fromPreset = false});
  final PartType? part; // set for catalog parts; null for platform/basket/button
  final String preset; // 'platform' | 'basket' | 'button' (non-empty only for those)
  final bool fromPreset; // true = came from stage.preset, false = player placement
}

/// Fixture-level tag on the basket's inner sensor fixture.
const _basketSensorTag = 'basket_sensor';

/// Fixture-level tag on the button's top-face press sensor fixture.
const _buttonSensorTag = 'button_sensor';

class SimWorld {
  SimWorld(this.stage, this.placements) {
    _build();
  }

  final StageData stage;
  final List<Placement> placements;
  final World world = World(Vector2(0, 10));
  static const double dt = 1 / 60;
  bool cleared = false;
  int stepCount = 0;
  final List<Body> _destroyQueue = [];

  // pop_balloons / topple_dominoes count only preset-origin parts (fromPreset
  // == true); a player-placed balloon/domino never contributes. press_button
  // latches once and never resets, matching `cleared`'s own latch semantics.
  int poppedPresetCount = 0;
  int _presetBalloonTotal = 0;
  int _presetDominoTotal = 0;
  bool _buttonPressed = false;

  void _build() {
    world.setContactListener(_GoalContactListener(this));
    for (final p in stage.preset) {
      if (p.type == 'platform') {
        _buildPlatform(p);
      } else if (p.type == 'basket') {
        _buildBasket(p);
      } else if (p.type == 'button') {
        _buildButton(p);
      } else {
        _buildCatalogBody(partTypeFromJson(p.type), p.x, p.y, p.angleDeg,
            fromPreset: true);
      }
    }
    for (final pl in placements) {
      _buildCatalogBody(pl.type, pl.x, pl.y, pl.angleDeg, fromPreset: false);
    }
    _presetBalloonTotal = _countFromPreset(PartType.balloon);
    _presetDominoTotal = _countFromPreset(PartType.domino);
  }

  int _countFromPreset(PartType type) => world.bodies.where((b) {
        final tag = b.userData as PartTag?;
        return tag?.part == type && tag!.fromPreset;
      }).length;

  // Any catalog PartType -> single-fixture body (circle if the spec has a
  // radius, box otherwise), plus the couple of per-type extras wired in
  // below (seesaw's center pivot, tack's sensor flag). Covers
  // plank/rubberBall/metalBall/balloon/domino/trampoline/seesaw fully, and is
  // a reasonable physical stand-in for the remaining joint/compound parts
  // (gear family, paddleGear, fan).
  // ponytail: gear revolute+motor joints, paddleGear's paddle box, and fan's
  // local wind force aren't built yet - single-fixture body only. Upgrade in
  // T5 when those behaviors are actually needed.
  Body _buildCatalogBody(PartType type, double x, double y, double angleDeg,
      {required bool fromPreset}) {
    final spec = Catalog.of(type);
    final isStatic = spec.density == null;
    final body = world.createBody(BodyDef(
      type: isStatic ? BodyType.static : BodyType.dynamic,
      position: Vector2(x, y),
      angle: angleDeg * pi / 180,
      userData: PartTag(part: type, fromPreset: fromPreset),
    ));
    final shape = spec.radius != null
        ? CircleShape(radius: spec.radius!)
        : (PolygonShape()..setAsBoxXY(spec.w! / 2, spec.h! / 2));
    body.createFixture(FixtureDef(
      shape,
      density: spec.density ?? 0,
      friction: spec.friction,
      restitution: spec.restitution,
      // tack IS a sensor by definition (contract table) - never a solid
      // obstacle, even though pop-on-touch is wired up in a later task.
      isSensor: type == PartType.tack,
    ));
    if (!isStatic) {
      body.gravityScale = Vector2(spec.gravityScale, spec.gravityScale);
      if (spec.linearDamping != null) {
        body.linearDamping = spec.linearDamping!;
      }
    }
    if (type == PartType.seesaw) {
      // Pin the plank to a static anchor at its own center so it teeters
      // instead of falling. body.worldCenter == (x, y) here since the box
      // fixture has no local offset.
      // A real seesaw's tilt is bounded by its ends touching the ground on
      // either side; without a limit here a free pivot just spins like a
      // propeller once anything uneven sits on one end (verified against
      // this exact failure while tuning the parts_test seesaw case).
      final pin = world.createBody(BodyDef(
        type: BodyType.static,
        position: Vector2(x, y),
      ));
      final pivot = RevoluteJointDef()
        ..initialize(pin, body, body.worldCenter)
        ..enableLimit = true
        ..lowerAngle = -0.6
        ..upperAngle = 0.6;
      world.createJoint(RevoluteJoint(pivot));
    }
    return body;
  }

  void _buildPlatform(PresetObject p) {
    final body = world.createBody(BodyDef(
      type: BodyType.static,
      position: Vector2(p.x, p.y),
      angle: p.angleDeg * pi / 180,
      userData: const PartTag(preset: 'platform', fromPreset: true),
    ));
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBoxXY(p.w! / 2, 0.2),
      friction: 0.6,
      restitution: 0.1,
    ));
  }

  void _buildButton(PresetObject p) {
    final body = world.createBody(BodyDef(
      type: BodyType.static,
      position: Vector2(p.x, p.y),
      angle: p.angleDeg * pi / 180,
      userData: const PartTag(preset: 'button', fromPreset: true),
    ));
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBoxXY(0.4, 0.11),
      friction: 0.5,
    ));
    // Top-face press sensor, straddling the box's top surface (local y =
    // -0.11 in this y-down frame) so it overlaps as soon as anything rests
    // on top, matching the basket sensor's "generous straddle" pattern.
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBox(0.38, 0.05, Vector2(0, -0.11), 0),
      isSensor: true,
      userData: _buttonSensorTag,
    ));
  }

  // Compound static body: floor + two side walls + an inner sensor fixture.
  // Local layout (anchor at the basket's own (x, y)):
  //   floor top sits at +0.3 (flush with the standard main-platform top, see
  //   the shared-contract example stage), walls rise from there to -0.3, and
  //   the sensor is centered on the anchor so a ball resting on the floor
  //   (center at y=0 local) sits inside it.
  void _buildBasket(PresetObject p) {
    final body = world.createBody(BodyDef(
      type: BodyType.static,
      position: Vector2(p.x, p.y),
      angle: p.angleDeg * pi / 180,
      userData: const PartTag(preset: 'basket', fromPreset: true),
    ));
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBox(0.5, 0.06, Vector2(0, 0.36), 0),
      friction: 0.5,
      restitution: 0.1,
    ));
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBox(0.06, 0.3, Vector2(-0.44, 0), 0),
      friction: 0.5,
      restitution: 0.1,
    ));
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBox(0.06, 0.3, Vector2(0.44, 0), 0),
      friction: 0.5,
      restitution: 0.1,
    ));
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBox(0.35, 0.175, Vector2(0, 0), 0),
      isSensor: true,
      userData: _basketSensorTag,
    ));
  }

  void step() {
    // (Task 5에서 바람 힘 추가 지점)
    world.stepDt(dt);
    for (final b in world.bodies.toList()) {
      final p = b.position;
      if (p.x < -2 || p.x > 18 || p.y > 11 || p.y < -2) _destroyQueue.add(b);
    }
    for (final b in _destroyQueue) {
      world.destroyBody(b);
    }
    _destroyQueue.clear();
    _checkGoal(); // ball_in_basket은 리스너 래치, 나머지는 Task 4
    stepCount++;
  }

  void _checkGoal() {
    if (cleared) return;
    if (stage.goal.type == GoalType.pressButton && _buttonPressed) {
      cleared = true;
    } else if (stage.goal.type == GoalType.popBalloons &&
        _presetBalloonTotal > 0 &&
        poppedPresetCount >= _presetBalloonTotal) {
      cleared = true;
    } else if (stage.goal.type == GoalType.toppleDominoes &&
        _dominoesAllToppled()) {
      cleared = true;
    }
    // ball_in_basket은 _GoalContactListener.beginContact가 직접 래치한다.
  }

  bool _dominoesAllToppled() {
    if (_presetDominoTotal == 0) return false;
    return !world.bodies.any((b) {
      final tag = b.userData as PartTag?;
      return tag?.part == PartType.domino &&
          tag!.fromPreset &&
          b.angle.abs() <= 0.7;
    });
  }

  // Queues a popped balloon for removal (processed after stepDt returns,
  // alongside the off-screen cleanup queue) and counts it toward the
  // pop_balloons goal only if it came from the stage preset.
  void _popBalloon(Body b) {
    if (_destroyQueue.contains(b)) return;
    _destroyQueue.add(b);
    if ((b.userData as PartTag?)?.fromPreset == true) {
      poppedPresetCount++;
    }
  }

  static bool verify(StageData s, List<Placement> p, {int maxSteps = 1800}) {
    final w = SimWorld(s, p);
    for (var i = 0; i < maxSteps && !w.cleared; i++) {
      w.step();
    }
    return w.cleared;
  }
}

class _GoalContactListener extends ContactListener {
  _GoalContactListener(this._sim);
  final SimWorld _sim;

  @override
  void beginContact(Contact contact) {
    final a = contact.fixtureA;
    final b = contact.fixtureB;
    if (_ballEnteredBasket(a, b)) {
      _sim.cleared = true;
    }
    _maybePopBalloon(a, b);
    _maybePressButton(a, b);
  }

  bool _ballEnteredBasket(Fixture a, Fixture b) {
    final Fixture other;
    if (a.userData == _basketSensorTag) {
      other = b;
    } else if (b.userData == _basketSensorTag) {
      other = a;
    } else {
      return false;
    }
    final tag = other.body.userData as PartTag?;
    return tag?.part == PartType.rubberBall || tag?.part == PartType.metalBall;
  }

  void _maybePopBalloon(Fixture a, Fixture b) {
    if (_isTack(a) && _isBalloon(b)) {
      _sim._popBalloon(b.body);
    } else if (_isTack(b) && _isBalloon(a)) {
      _sim._popBalloon(a.body);
    }
  }

  bool _isTack(Fixture f) => (f.body.userData as PartTag?)?.part == PartType.tack;
  bool _isBalloon(Fixture f) =>
      (f.body.userData as PartTag?)?.part == PartType.balloon;

  void _maybePressButton(Fixture a, Fixture b) {
    if (a.userData == _buttonSensorTag && _isDynamicSolid(b)) {
      _sim._buttonPressed = true;
    } else if (b.userData == _buttonSensorTag && _isDynamicSolid(a)) {
      _sim._buttonPressed = true;
    }
  }

  bool _isDynamicSolid(Fixture f) =>
      !f.isSensor && f.body.bodyType == BodyType.dynamic;
}

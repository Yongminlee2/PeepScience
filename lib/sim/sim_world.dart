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
  }

  // Any catalog PartType -> single-fixture body (circle if the spec has a
  // radius, box otherwise). Covers plank/rubberBall/metalBall/balloon/domino/
  // trampoline plus a reasonable physical stand-in for the joint/compound
  // parts (gear family, paddleGear, fan, seesaw).
  // ponytail: gear revolute joints, paddleGear's paddle box, seesaw's pivot
  // and fan's local wind force aren't built yet - single-fixture body only.
  // Upgrade in T5 (gears/fan) when those behaviors are actually needed.
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
    // Physical box only for now; the top-face press sensor + latch belongs
    // to the press_button goal check added in T4.
    body.createFixture(FixtureDef(
      PolygonShape()..setAsBoxXY(0.4, 0.11),
      friction: 0.5,
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
    // ball_in_basket은 _GoalContactListener.beginContact가 cleared를 래치.
    // press_button / pop_balloons / topple_dominoes 카운트는 Task 4에서 추가.
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
    if (_ballEnteredBasket(contact.fixtureA, contact.fixtureB)) {
      _sim.cleared = true;
    }
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
}

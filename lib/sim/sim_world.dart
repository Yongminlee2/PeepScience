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
  final List<_FanZone> _fanZones = [];
  final List<_GearPin> _gearPins = [];

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
    _meshGears();
  }

  // Pairwise: any two gear-family bodies whose centers are within
  // r1+r2+0.05 of each other get a GearJoint linking their revolute pins.
  // A 3-gear chain (A-B-C) just gets two pairwise joints (A-B, B-C) - no
  // separate chain-handling needed. 0.05 slack above the exact meshing
  // distance covers rounding from the placement snap; test/preset stages
  // place gears explicitly so this never over-matches in practice.
  void _meshGears() {
    for (var i = 0; i < _gearPins.length; i++) {
      for (var j = i + 1; j < _gearPins.length; j++) {
        final a = _gearPins[i];
        final b = _gearPins[j];
        final dist = (a.body.position - b.body.position).length;
        if (dist > a.radius + b.radius + 0.05) continue;
        final def = GearJointDef()
          ..bodyA = a.body
          ..bodyB = b.body
          ..joint1 = a.pin
          ..joint2 = b.pin
          // Externally meshed gears spin opposite ways: the GearJoint
          // constraint is coordinateA + ratio*coordinateB = const, so
          // omegaB = -omegaA/ratio. Opposite sign needs ratio > 0; matching
          // the physical rolling-contact relation omegaB/omegaA = -rA/rB
          // gives ratio = rB/rA (verified against gear_joint.dart's own
          // coordinate formula, not guessed).
          ..ratio = b.radius / a.radius;
        world.createJoint(GearJoint(def));
      }
    }
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
  // (gear family, paddleGear, fan) — 관절·바람 등 타입별 추가 배선은 아래에서.
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
        ..lowerAngle = -spec.jointLimit!
        ..upperAngle = spec.jointLimit!;
      world.createJoint(RevoluteJoint(pivot));
    } else if (type == PartType.motorGear ||
        type == PartType.gear ||
        type == PartType.paddleGear) {
      if (type == PartType.paddleGear) {
        // Paddle arm straight through the gear's own center (spans both
        // sides). Same PartSpec drives both fixtures - it's the only
        // density/friction/restitution record paddleGear has.
        body.createFixture(FixtureDef(
          PolygonShape()..setAsBoxXY(spec.w! / 2, spec.h! / 2),
          density: spec.density!,
          friction: spec.friction,
          restitution: spec.restitution,
        ));
      }
      // Free-spinning revolute pin at the gear's own center - no angle
      // limit (unlike the seesaw), so a meshed pair's GearJoint can spin it
      // continuously.
      // 톱니 전달은 GearJoint 방식. 마찰 전달은 핀 고정 원끼리 수직항력이
      // 0이라 물리적으로 불가 — docs/개발일지.md 2차 참고.
      final pin = world.createBody(BodyDef(
        type: BodyType.static,
        position: Vector2(x, y),
      ));
      final jointDef = RevoluteJointDef()
        ..initialize(pin, body, body.worldCenter);
      if (type == PartType.motorGear) {
        jointDef.enableMotor = true;
        jointDef.motorSpeed = spec.motorSpeed!;
        jointDef.maxMotorTorque = spec.motorTorque!;
      }
      final revolute = RevoluteJoint(jointDef);
      world.createJoint(revolute);
      _gearPins.add(_GearPin(body, revolute, spec.radius!));
    } else if (type == PartType.fan) {
      _fanZones.add(_FanZone(body, spec));
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
    for (final zone in _fanZones) {
      for (final b in world.bodies) {
        zone.pushIfInside(b);
      }
    }
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

// A gear-family body plus the RevoluteJoint pinning it to its own static
// anchor, kept around so _meshGears can link meshed pairs with a GearJoint.
class _GearPin {
  _GearPin(this.body, this.pin, this.radius);
  final Body body;
  final RevoluteJoint pin;
  final double radius;
}

// A fan's push zone: a 3.0(long) x 0.8(wide) rectangle starting at the fan's
// own +x face, rotated by the fan's angle. Fans are static so their
// position/angle never change after this - dir/perp (the rotated local
// +x/+y axes) are computed once here instead of every step.
class _FanZone {
  _FanZone(Body fan, PartSpec spec)
      : origin = fan.position.clone(),
        dir = Vector2(cos(fan.angle), sin(fan.angle)),
        perp = Vector2(-sin(fan.angle), cos(fan.angle)),
        near = spec.w! / 2,
        far = spec.w! / 2 + _zoneLength,
        halfWidth = _zoneWidth / 2,
        force = spec.windForce!;

  static const _zoneLength = 3.0;
  static const _zoneWidth = 0.8;

  final Vector2 origin;
  final Vector2 dir;
  final Vector2 perp;
  final double near;
  final double far;
  final double halfWidth;
  final double force;

  void pushIfInside(Body b) {
    if (b.bodyType != BodyType.dynamic) return;
    final rel = b.position - origin;
    final along = rel.dot(dir);
    if (along < near || along > far) return;
    if (rel.dot(perp).abs() > halfWidth) return;
    b.applyForce(dir * force);
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

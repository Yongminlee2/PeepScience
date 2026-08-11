enum PartType {
  plank,
  rubberBall,
  metalBall,
  balloon,
  domino,
  seesaw,
  motorGear,
  gear,
  paddleGear,
  fan,
  trampoline,
  tack
}

enum GoalType { ballInBasket, pressButton, popBalloons, toppleDominoes }

/// Physical properties for a part type
class PartSpec {
  final double? radius; // for circles
  final double? w; // width for rectangles
  final double? h; // height for rectangles
  final double? density; // null for static objects
  final double friction;
  final double restitution;
  final bool rotatable;
  final double gravityScale;
  final double? linearDamping; // for balloon
  final double? motorSpeed; // for motorGear (rad/s)
  final double? motorTorque; // for motorGear

  const PartSpec({
    this.radius,
    this.w,
    this.h,
    this.density,
    required this.friction,
    required this.restitution,
    required this.rotatable,
    required this.gravityScale,
    this.linearDamping,
    this.motorSpeed,
    this.motorTorque,
  });
}

/// Catalog of physical properties for each part type
class Catalog {
  static PartSpec of(PartType type) {
    return switch (type) {
      PartType.plank => const PartSpec(
          w: 2.0,
          h: 0.24,
          density: null, // static
          friction: 0.5,
          restitution: 0.1,
          rotatable: true,
          gravityScale: 1.0,
        ),
      PartType.rubberBall => const PartSpec(
          radius: 0.3,
          density: 1.0,
          friction: 0.3,
          restitution: 0.75,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.metalBall => const PartSpec(
          radius: 0.3,
          density: 7.0,
          friction: 0.3,
          restitution: 0.05,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.balloon => const PartSpec(
          radius: 0.4,
          density: 0.1,
          friction: 0.1,
          restitution: 0.2,
          rotatable: false,
          gravityScale: -0.5,
          linearDamping: 1.5,
        ),
      PartType.domino => const PartSpec(
          w: 0.24,
          h: 0.9,
          density: 1.0,
          friction: 0.4,
          restitution: 0.05,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.seesaw => const PartSpec(
          w: 2.6,
          h: 0.2,
          density: 1.0,
          friction: 0.5,
          restitution: 0.1,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.motorGear => const PartSpec(
          radius: 0.5,
          density: 2.0,
          friction: 1.0,
          restitution: 0.0,
          rotatable: false,
          gravityScale: 1.0,
          motorSpeed: 2.5,
          motorTorque: 50,
        ),
      PartType.gear => const PartSpec(
          radius: 0.5,
          density: 2.0,
          friction: 1.0,
          restitution: 0.0,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.paddleGear => const PartSpec(
          radius: 0.5,
          w: 1.4,
          h: 0.15,
          density: 0.5,
          friction: 0.8,
          restitution: 0.1,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.fan => const PartSpec(
          w: 0.5,
          h: 0.8,
          density: null, // static
          friction: 0.5,
          restitution: 0.0,
          rotatable: true,
          gravityScale: 1.0,
        ),
      PartType.trampoline => const PartSpec(
          w: 1.2,
          h: 0.3,
          density: null, // static
          friction: 0.8,
          restitution: 1.1,
          rotatable: false,
          gravityScale: 1.0,
        ),
      PartType.tack => const PartSpec(
          radius: 0.12,
          density: null, // static
          friction: 0.0,
          restitution: 0.0,
          rotatable: false,
          gravityScale: 1.0,
        ),
    };
  }
}

/// Convert JSON id string (snake_case) to PartType enum
PartType partTypeFromJson(String id) {
  return switch (id) {
    'plank' => PartType.plank,
    'rubber_ball' => PartType.rubberBall,
    'metal_ball' => PartType.metalBall,
    'balloon' => PartType.balloon,
    'domino' => PartType.domino,
    'seesaw' => PartType.seesaw,
    'motor_gear' => PartType.motorGear,
    'gear' => PartType.gear,
    'paddle_gear' => PartType.paddleGear,
    'fan' => PartType.fan,
    'trampoline' => PartType.trampoline,
    'tack' => PartType.tack,
    _ => throw FormatException('Unknown part type: $id'),
  };
}

/// Convert PartType enum to JSON id string (snake_case)
String jsonIdOf(PartType type) {
  return switch (type) {
    PartType.plank => 'plank',
    PartType.rubberBall => 'rubber_ball',
    PartType.metalBall => 'metal_ball',
    PartType.balloon => 'balloon',
    PartType.domino => 'domino',
    PartType.seesaw => 'seesaw',
    PartType.motorGear => 'motor_gear',
    PartType.gear => 'gear',
    PartType.paddleGear => 'paddle_gear',
    PartType.fan => 'fan',
    PartType.trampoline => 'trampoline',
    PartType.tack => 'tack',
  };
}

/// Convert GoalType to JSON id string (snake_case)
String goalJsonIdOf(GoalType type) {
  return switch (type) {
    GoalType.ballInBasket => 'ball_in_basket',
    GoalType.pressButton => 'press_button',
    GoalType.popBalloons => 'pop_balloons',
    GoalType.toppleDominoes => 'topple_dominoes',
  };
}

/// Convert JSON id string (snake_case) to GoalType enum
GoalType goalTypeFromJson(String id) {
  return switch (id) {
    'ball_in_basket' => GoalType.ballInBasket,
    'press_button' => GoalType.pressButton,
    'pop_balloons' => GoalType.popBalloons,
    'topple_dominoes' => GoalType.toppleDominoes,
    _ => throw FormatException('Unknown goal type: $id'),
  };
}

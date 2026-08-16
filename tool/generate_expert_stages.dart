import 'dart:convert';
import 'dart:io';

/// Generates the expert half (11-20) of every world from proven physical
/// motifs in the first half. A transform first preserves a generous landing
/// window, then [_configureExpertMechanism] turns previously prebuilt pieces
/// into player-built machinery or composes multiple independent chains.
///
/// Run from the repository root:
///   dart run tool/generate_expert_stages.dart
void main() {
  const stagesDir = 'assets/stages';

  for (var world = 1; world <= 4; world++) {
    for (var sourceIndex = 1; sourceIndex <= 10; sourceIndex++) {
      final sourceId = _stageId(world, sourceIndex);
      final targetIndex = sourceIndex + 10;
      final targetId = _stageId(world, targetIndex);
      final sourceFile = File('$stagesDir/$sourceId.json');
      final stage =
          jsonDecode(sourceFile.readAsStringSync()) as Map<String, dynamic>;

      // A few bank-shot layouts are intentionally asymmetric enough that a
      // literal mirror loses their generous landing window. They join the
      // motor stages on the relocation path instead.
      final useRelocation =
          const {'w1_s01', 'w1_s02', 'w2_s06'}.contains(sourceId) ||
          world == 3 ||
          (world == 4 && (sourceIndex == 6 || sourceIndex == 8));
      if (useRelocation) {
        _relocateHorizontally(
          stage,
          dxOverride: sourceId == 'w2_s06' ? 4 : null,
        );
      } else {
        _mirrorHorizontally(stage);
      }

      _configureExpertMechanism(stage, world, sourceIndex);
      _lockGoalCarriers(stage);
      stage['id'] = targetId;
      stage['index'] = targetIndex;
      _offerSparePart(stage);
      stage['challenge'] = _challengeFor(stage);
      _applyPresentationHooks(world, targetIndex, stage);

      File('$stagesDir/$targetId.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(stage)}\n',
      );
    }
  }
}

/// Mastery stages never put the object that directly satisfies the goal in
/// the tray. A player may build ramps, launchers and guides, but cannot win by
/// dropping a ball over the basket/button or placing a tack on a balloon.
void _lockGoalCarriers(Map<String, dynamic> stage) {
  final goal = (stage['goal'] as Map<String, dynamic>)['type'] as String;
  final lockedTypes = switch (goal) {
    'ball_in_basket' ||
    'press_button' ||
    'topple_dominoes' => const {'rubber_ball', 'metal_ball'},
    'pop_balloons' => const {'tack'},
    _ => const <String>{},
  };

  final solution = stage['solution'] as List<dynamic>;
  final preset = stage['preset'] as List<dynamic>;
  for (var index = solution.length - 1; index >= 0; index--) {
    final placement = solution[index] as Map<String, dynamic>;
    if (!lockedTypes.contains(placement['type'])) continue;
    preset.add(Map<String, dynamic>.from(placement));
    solution.removeAt(index);
  }

  final tray = stage['tray'] as List<dynamic>;
  tray.removeWhere(
    (raw) => lockedTypes.contains((raw as Map<String, dynamic>)['type']),
  );
}

void _configureExpertMechanism(
  Map<String, dynamic> stage,
  int world,
  int sourceIndex,
) {
  switch (world) {
    case 1:
      // Never hand the goal ball to the player in mastery stages. The old
      // remix did exactly that, so dropping it over the basket bypassed the
      // whole machine. These are authored as long, interrupted tracks: the
      // ball is locked at the launcher and every missing bridge becomes a
      // real fall hazard.
      _buildPlankGauntlet(stage, sourceIndex);
    case 2:
      switch (sourceIndex) {
        case 1 || 2 || 4 || 5 || 6 || 7 || 9 || 10:
          _buildSeesawTrampolineCourse(stage, sourceIndex);
        case 3:
          _buildBalloonGuideStage(stage, mirroredPair: true, leftBalloonX: 3.5);
        case 8:
          _buildBalloonGuideStage(stage, mirroredPair: true);
      }
    case 3:
      switch (sourceIndex) {
        case 1 || 2 || 3 || 4 || 5 || 6 || 8:
          // The early factory supplied its motor. Expert stages require the
          // full drive train to be assembled by the player.
          _promotePreset(stage, 'motor_gear', insertAtStart: true);
        case 7:
          // Build all three meshed gears instead of merely choosing where to
          // add the motor.
          _promotePreset(stage, 'gear');
          _promotePreset(stage, 'paddle_gear');
          for (final type in ['motor_gear', 'gear', 'paddle_gear']) {
            final gear = _firstSolution(stage, type);
            gear['x'] = _clean((gear['x'] as num).toDouble() - 0.06);
          }
        case 9:
          // The falling gear still steers the balloon, but the player must
          // now position the needle that completes the pop chain as well.
          _promotePreset(stage, 'tack');
        case 10:
          // Assemble and load the complete three-gear launcher.
          final ball = _firstPreset(stage, 'rubber_ball');
          ball
            ..['x'] = _clean((ball['x'] as num).toDouble() - 0.2)
            // Deliberately authored between the paddle/gear envelope below
            // and the platform above. Keep the literal (rather than a
            // subtraction that becomes 4.819999...) so the shared AABB
            // legality check sees the intended 5mm clearance.
            ..['y'] = 4.825;
          _promotePreset(stage, 'rubber_ball');
          final basket = _firstPreset(stage, 'basket');
          basket
            ..['x'] = 4.7
            ..['y'] = 6;
      }
      _expandGearTrain(stage, sourceIndex);
    case 4:
      switch (sourceIndex) {
        case 1:
          _buildFanPlankButtonCourse(stage);
        case 2:
          _buildFactoryWindStage(stage);
        case 3:
          _buildWindBalloonMaze(stage, twin: true, verticalShift: -0.3);
        case 4:
          _buildWindSeesawCourse(stage, dx: -1.5);
        case 5:
          _buildWindBalloonMaze(stage, twin: true);
        case 6:
          _promotePreset(stage, 'motor_gear', insertAtStart: true);
          _promotePreset(stage, 'fan');
        case 7:
          _buildWindSeesawCourse(stage);
        case 8:
          _buildFactoryBounceStage(stage);
        case 9:
          _buildTwinFanDominoStage(stage);
        case 10:
          _buildWindBalloonMaze(stage, twin: true, verticalShift: -0.15);
      }
  }
}

void _expandGearTrain(Map<String, dynamic> stage, int variant) {
  if (variant == 9) {
    stage
      ..['goal'] = {'type': 'pop_balloons'}
      ..['preset'] = [
        {'type': 'balloon', 'x': 12.45, 'y': 7, 'angle': 0},
        {'type': 'tack', 'x': 13, 'y': 3, 'angle': 0},
        {'type': 'balloon', 'x': 3.55, 'y': 7, 'angle': 0},
        {'type': 'tack', 'x': 3, 'y': 3, 'angle': 0},
      ]
      ..['tray'] = [
        {'type': 'gear', 'count': 2},
      ]
      ..['solution'] = [
        {'type': 'gear', 'x': 11.7, 'y': 6, 'angle': 0},
        {'type': 'gear', 'x': 4.3, 'y': 6, 'angle': 0},
      ]
      ..remove('prediction');
    return;
  }

  final solution = (stage['solution'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final motorIndex = solution.indexWhere(
    (placement) => placement['type'] == 'motor_gear',
  );
  if (motorIndex == -1) {
    throw StateError('Expert gear stage $variant has no player motor');
  }
  final motor = solution[motorIndex];
  final oldX = (motor['x'] as num).toDouble();
  final y = (motor['y'] as num).toDouble();
  final neighbor = solution.firstWhere(
    (placement) =>
        placement != motor &&
        const {'gear', 'paddle_gear'}.contains(placement['type']),
  );
  final direction = (neighbor['x'] as num).toDouble() > oldX ? 1.0 : -1.0;
  motor['x'] = _clean(oldX - 1.94 * direction);
  solution.insertAll(motorIndex + 1, [
    {
      'type': 'gear',
      'x': _clean(oldX - 0.97 * direction),
      'y': _clean(y),
      'angle': 0,
    },
    {'type': 'gear', 'x': _clean(oldX), 'y': _clean(y), 'angle': 0},
  ]);
  _addTray(stage, 'gear');
  _addTray(stage, 'gear');
  if (variant == 6 || variant == 8) {
    final basket = _firstPreset(stage, 'basket');
    basket
      ..['x'] = variant == 6 ? 12.37 : 11.77
      ..['y'] = variant == 6 ? 5.6 : 5.5;
  }
}

void _buildFanPlankButtonCourse(Map<String, dynamic> stage) {
  stage
    ..['goal'] = {'type': 'press_button'}
    ..['preset'] = [
      {'type': 'platform', 'x': 4.98, 'y': 7, 'angle': 0, 'w': 2.95},
      {'type': 'rubber_ball', 'x': 4.5, 'y': 6.5, 'angle': 0},
      {'type': 'button', 'x': 9, 'y': 6.5, 'angle': 0},
    ]
    ..['tray'] = [
      {'type': 'fan', 'count': 1},
      {'type': 'plank', 'count': 1},
    ]
    ..['solution'] = [
      {'type': 'fan', 'x': 2.9, 'y': 6.8, 'angle': -2},
      {'type': 'plank', 'x': 7.5, 'y': 7, 'angle': -18},
    ]
    ..remove('prediction');
}

void _buildFactoryWindStage(Map<String, dynamic> stage) {
  stage
    ..['goal'] = {'type': 'ball_in_basket'}
    ..['preset'] = [
      {'type': 'platform', 'x': 9.97, 'y': 6.35, 'angle': 0, 'w': 1},
      {'type': 'rubber_ball', 'x': 9.97, 'y': 5.85, 'angle': 0},
      {'type': 'basket', 'x': 12, 'y': 6.75, 'angle': 0},
    ]
    ..['tray'] = [
      {'type': 'motor_gear', 'count': 1},
      {'type': 'paddle_gear', 'count': 1},
      {'type': 'fan', 'count': 1},
    ]
    ..['solution'] = [
      {'type': 'motor_gear', 'x': 9, 'y': 5, 'angle': 0},
      {'type': 'paddle_gear', 'x': 9.97, 'y': 5, 'angle': 0},
      {'type': 'fan', 'x': 11, 'y': 7, 'angle': 0},
    ]
    ..remove('prediction');
}

void _buildWindBalloonMaze(
  Map<String, dynamic> stage, {
  required bool twin,
  double verticalShift = 0,
}) {
  stage
    ..['goal'] = {'type': 'pop_balloons'}
    ..['preset'] = [
      {'type': 'balloon', 'x': 14, 'y': 7 + verticalShift, 'angle': 0},
      {'type': 'tack', 'x': 11.73, 'y': 0.35 + verticalShift, 'angle': 0},
      if (twin) ...[
        {'type': 'balloon', 'x': 2, 'y': 7 + verticalShift, 'angle': 0},
        {'type': 'tack', 'x': 4.27, 'y': 0.35 + verticalShift, 'angle': 0},
      ],
    ]
    ..['tray'] = [
      {'type': 'plank', 'count': twin ? 2 : 1},
      {'type': 'fan', 'count': twin ? 2 : 1},
      {'type': 'gear', 'count': twin ? 2 : 1},
    ]
    ..['solution'] = [
      {'type': 'plank', 'x': 14, 'y': 5 + verticalShift, 'angle': 0},
      {'type': 'fan', 'x': 15.65, 'y': 5.6 + verticalShift, 'angle': 180},
      {'type': 'gear', 'x': 10.5, 'y': 5.1 + verticalShift, 'angle': 0},
      if (twin) ...[
        {'type': 'plank', 'x': 2, 'y': 5 + verticalShift, 'angle': 0},
        {'type': 'fan', 'x': 0.35, 'y': 5.6 + verticalShift, 'angle': 0},
        {'type': 'gear', 'x': 5.5, 'y': 5.1 + verticalShift, 'angle': 0},
      ],
    ]
    ..['feature'] = 'chain_reaction'
    ..remove('prediction');
}

void _buildWindSeesawCourse(Map<String, dynamic> stage, {double dx = 0}) {
  stage
    ..['goal'] = {'type': 'ball_in_basket'}
    ..['preset'] = [
      {'type': 'rubber_ball', 'x': 8 + dx, 'y': 4.07, 'angle': 0},
      {'type': 'basket', 'x': 3.6 + dx, 'y': 4.5, 'angle': 0},
    ]
    ..['tray'] = [
      {'type': 'fan', 'count': 1},
      {'type': 'trampoline', 'count': 1},
      {'type': 'seesaw', 'count': 1},
    ]
    ..['solution'] = [
      {'type': 'fan', 'x': 10.3 + dx, 'y': 4.3, 'angle': 178},
      {'type': 'trampoline', 'x': 5.4 + dx, 'y': 6.3, 'angle': 0},
      {'type': 'seesaw', 'x': 8 + dx, 'y': 4.5, 'angle': 0},
    ]
    ..remove('prediction');
}

void _buildBalloonGuideStage(
  Map<String, dynamic> stage, {
  required bool mirroredPair,
  double leftBalloonX = 4,
}) {
  final dx = leftBalloonX - 4;
  final preset = <Map<String, dynamic>>[
    {'type': 'balloon', 'x': 4 + dx, 'y': 7, 'angle': 0},
    {'type': 'tack', 'x': 6 + dx, 'y': 0.5, 'angle': 0},
    if (mirroredPair) ...[
      {'type': 'balloon', 'x': 12 - dx, 'y': 7, 'angle': 0},
      {'type': 'tack', 'x': 10 - dx, 'y': 0.5, 'angle': 0},
    ],
  ];
  final solution = <Map<String, dynamic>>[
    {'type': 'plank', 'x': 3.5 + dx, 'y': 4.5, 'angle': -45},
    {'type': 'plank', 'x': 4.5 + dx, 'y': 2, 'angle': 0},
    if (mirroredPair) ...[
      {'type': 'plank', 'x': 12.5 - dx, 'y': 4.5, 'angle': 45},
      {'type': 'plank', 'x': 11.5 - dx, 'y': 2, 'angle': 0},
    ],
  ];
  stage
    ..['goal'] = {'type': 'pop_balloons'}
    ..['preset'] = preset
    ..['tray'] = [
      {'type': 'plank', 'count': solution.length},
    ]
    ..['solution'] = solution
    ..remove('prediction');
}

void _buildSeesawTrampolineCourse(Map<String, dynamic> stage, int variant) {
  final dx = switch (variant) {
    1 => -1.5,
    2 => -0.5,
    4 => 0.0,
    5 => 1.5,
    6 => 2.25,
    7 => 3.0,
    9 => -0.75,
    _ => 0.75,
  };
  final preset = <Map<String, dynamic>>[
    {'type': 'rubber_ball', 'x': 5.8 + dx, 'y': 5.57, 'angle': 0},
    {'type': 'metal_ball', 'x': 8.3 + dx, 'y': 4.8, 'angle': 0},
    {'type': 'basket', 'x': 3 + dx, 'y': 5.5, 'angle': 0},
  ];
  final solution = <Map<String, dynamic>>[
    {'type': 'seesaw', 'x': 7 + dx, 'y': 6, 'angle': 0},
    {'type': 'trampoline', 'x': 4.77 + dx, 'y': 6.85, 'angle': 0},
    {'type': 'trampoline', 'x': 3.25 + dx, 'y': 6.9, 'angle': 0},
  ];
  for (final object in [...preset, ...solution]) {
    object['x'] = _clean((object['x'] as num).toDouble());
  }
  stage
    ..['goal'] = {'type': 'ball_in_basket'}
    ..['preset'] = preset
    ..['tray'] = [
      {'type': 'seesaw', 'count': 1},
      {'type': 'trampoline', 'count': 2},
    ]
    ..['solution'] = solution
    ..remove('prediction');
}

void _buildPlankGauntlet(Map<String, dynamic> stage, int variant) {
  final originalGoal =
      ((stage['goal'] as Map<String, dynamic>)['type'] as String);
  final courseGoal = originalGoal == 'topple_dominoes'
      ? 'press_button'
      : originalGoal;
  final fourPartCourse = variant >= 4;

  final preset = <Map<String, dynamic>>[
    {'type': 'rubber_ball', 'x': 14, 'y': 1, 'angle': 0},
    if (fourPartCourse) ...[
      {'type': 'platform', 'x': 13.03, 'y': 5.2, 'angle': 0, 'w': 3.95},
      {'type': 'platform', 'x': 8.48, 'y': 5.2, 'angle': 0, 'w': 0.95},
      {'type': 'platform', 'x': 5.43, 'y': 5.2, 'angle': 0, 'w': 0.95},
      {'type': 'platform', 'x': 1.33, 'y': 5.2, 'angle': 0, 'w': 3.05},
    ] else ...[
      {'type': 'platform', 'x': 11.75, 'y': 5.2, 'angle': 0, 'w': 6.5},
      {
        'type': 'platform',
        'x': courseGoal == 'topple_dominoes' ? 5.75 : 5.4,
        'y': 5.2,
        'angle': 0,
        'w': courseGoal == 'topple_dominoes' ? 1.3 : 2,
      },
      {
        'type': 'platform',
        'x': courseGoal == 'topple_dominoes' ? 1.5 : 1.05,
        'y': 5.2,
        'angle': 0,
        'w': courseGoal == 'topple_dominoes' ? 3 : 2.5,
      },
    ],
  ];

  if (courseGoal == 'ball_in_basket') {
    // The final island is shortened so the ball must roll off into the
    // receiver below instead of merely touching a basket placed on-track.
    preset
      ..removeLast()
      ..add({
        'type': 'platform',
        'x': fourPartCourse ? 1.83 : 1.55,
        'y': 5.2,
        'angle': 0,
        'w': fourPartCourse ? 2.05 : 1.5,
      })
      ..add({'type': 'basket', 'x': 0.4, 'y': 5.4, 'angle': 0});
  } else if (courseGoal == 'topple_dominoes') {
    for (final x in [0.8, 1.2, 1.6, 2.0]) {
      preset.add({'type': 'domino', 'x': x, 'y': 4.5, 'angle': -15});
    }
  } else {
    preset.add({
      'type': 'button',
      'x': fourPartCourse ? 0.4 : 0.8,
      'y': fourPartCourse ? 5 : 5.11,
      'angle': 0,
    });
  }

  final solution = <Map<String, dynamic>>[
    {
      'type': 'plank',
      'x': 14,
      'y': 2.3,
      'angle': fourPartCourse && courseGoal == 'press_button' ? -26 : -28,
    },
    if (fourPartCourse) ...[
      {'type': 'plank', 'x': 10, 'y': 5.12, 'angle': 0},
      {'type': 'plank', 'x': 6.95, 'y': 5.12, 'angle': 0},
      {'type': 'plank', 'x': 3.9, 'y': 5.12, 'angle': 0},
    ] else ...[
      {'type': 'plank', 'x': 7.45, 'y': 5.12, 'angle': 0},
      {
        'type': 'plank',
        'x': courseGoal == 'topple_dominoes' ? 4.05 : 3.35,
        'y': 5.12,
        'angle': 0,
      },
    ],
  ];

  // Alternate the reading direction. Motor stages cannot be mirrored, but
  // this purely passive course can, and the two orientations prevent rote
  // memorisation of one launch corner.
  if (variant.isEven) {
    for (final object in [...preset, ...solution]) {
      object['x'] = _clean(16 - (object['x'] as num).toDouble());
      object['angle'] = _clean(-(object['angle'] as num).toDouble());
    }
  }
  if (variant == 10) {
    final challenge = stage['challenge'] as Map<String, dynamic>?;
    final star = challenge?['collectible_star'] as Map<String, dynamic>?;
    star
      ?..['x'] = 7.45
      ..['y'] = 3.8;
  }

  stage
    ..['goal'] = {'type': courseGoal}
    ..['preset'] = preset
    ..['tray'] = [
      {'type': 'plank', 'count': solution.length},
    ]
    ..['solution'] = solution
    ..remove('prediction');
}

void _buildTwinFanDominoStage(Map<String, dynamic> stage) {
  stage
    ..['goal'] = {'type': 'topple_dominoes'}
    ..['preset'] = [
      {'type': 'platform', 'x': 5, 'y': 7, 'angle': 0, 'w': 4},
      {'type': 'platform', 'x': 11, 'y': 7, 'angle': 0, 'w': 4},
      for (final x in [4.2, 4.8, 5.4, 6.0])
        {'type': 'domino', 'x': x, 'y': 6.35, 'angle': 0},
      for (final x in [10.2, 10.8, 11.4, 12.0])
        {'type': 'domino', 'x': x, 'y': 6.35, 'angle': 0},
    ]
    ..['tray'] = [
      {'type': 'fan', 'count': 2},
    ]
    ..['solution'] = [
      {'type': 'fan', 'x': 2.35, 'y': 7.1, 'angle': -30},
      {'type': 'fan', 'x': 8.35, 'y': 7.1, 'angle': -30},
    ]
    ..remove('prediction');
}

void _buildFactoryBounceStage(Map<String, dynamic> stage) {
  stage
    ..['goal'] = {'type': 'ball_in_basket'}
    ..['preset'] = [
      {'type': 'platform', 'x': 5, 'y': 5.35, 'angle': 0, 'w': 1},
      {'type': 'rubber_ball', 'x': 5, 'y': 4.85, 'angle': 0},
      {'type': 'basket', 'x': 7.4, 'y': 5.5, 'angle': 0},
    ]
    ..['tray'] = [
      {'type': 'motor_gear', 'count': 1},
      {'type': 'paddle_gear', 'count': 1},
      {'type': 'trampoline', 'count': 1},
    ]
    ..['solution'] = [
      {'type': 'motor_gear', 'x': 4.03, 'y': 4, 'angle': 0},
      {'type': 'paddle_gear', 'x': 5, 'y': 4, 'angle': 0},
      {'type': 'trampoline', 'x': 5.9, 'y': 6.2, 'angle': 0},
    ]
    ..remove('prediction');
}

Map<String, dynamic> _firstPreset(Map<String, dynamic> stage, String type) =>
    (stage['preset'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere(
      (object) => object['type'] == type,
    );

Map<String, dynamic> _firstSolution(Map<String, dynamic> stage, String type) =>
    (stage['solution'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((object) => object['type'] == type);

void _promotePreset(
  Map<String, dynamic> stage,
  String type, {
  bool last = false,
  bool insertAtStart = false,
}) {
  final preset = stage['preset'] as List<dynamic>;
  final index = last
      ? preset.lastIndexWhere(
          (raw) => (raw as Map<String, dynamic>)['type'] == type,
        )
      : preset.indexWhere(
          (raw) => (raw as Map<String, dynamic>)['type'] == type,
        );
  if (index == -1) {
    throw StateError('No $type preset to promote');
  }
  final source = preset.removeAt(index) as Map<String, dynamic>;
  final placement = <String, dynamic>{
    'type': type,
    'x': source['x'],
    'y': source['y'],
    'angle': source['angle'],
  };
  final solution = stage['solution'] as List<dynamic>;
  if (insertAtStart) {
    solution.insert(0, placement);
  } else {
    solution.add(placement);
  }
  _addTray(stage, type);
}

void _addTray(Map<String, dynamic> stage, String type) {
  final tray = stage['tray'] as List<dynamic>;
  final index = tray.indexWhere(
    (raw) => (raw as Map<String, dynamic>)['type'] == type,
  );
  if (index == -1) {
    tray.add({'type': type, 'count': 1});
    return;
  }
  final entry = tray[index] as Map<String, dynamic>;
  entry['count'] = (entry['count'] as int) + 1;
}

String _stageId(int world, int index) =>
    'w${world}_s${index.toString().padLeft(2, '0')}';

void _mirrorHorizontally(Map<String, dynamic> stage) {
  for (final key in ['preset', 'solution']) {
    for (final raw in stage[key] as List<dynamic>) {
      final object = raw as Map<String, dynamic>;
      object['x'] = _clean(16 - (object['x'] as num).toDouble());
      final angle = (object['angle'] as num).toDouble();
      object['angle'] = _clean(object['type'] == 'fan' ? 180 - angle : -angle);
    }
  }

  final challenge = stage['challenge'];
  if (challenge is Map<String, dynamic>) {
    final star = challenge['collectible_star'];
    if (star is Map<String, dynamic>) {
      star['x'] = _clean(16 - (star['x'] as num).toDouble());
    }
  }
}

/// Gear motors have a fixed clockwise direction. Mirroring a geared machine
/// would therefore change its behavior, so those stages keep their internal
/// orientation and move the whole contraption to the opposite side instead.
void _relocateHorizontally(Map<String, dynamic> stage, {double? dxOverride}) {
  final objects = <Map<String, dynamic>>[
    for (final raw in stage['preset'] as List<dynamic>)
      raw as Map<String, dynamic>,
    for (final raw in stage['solution'] as List<dynamic>)
      raw as Map<String, dynamic>,
  ];
  final xs = objects.map((object) => (object['x'] as num).toDouble());
  final minX = xs.reduce((a, b) => a < b ? a : b);
  final maxX = xs.reduce((a, b) => a > b ? a : b);
  final dx = dxOverride ?? _clean(16 - minX - maxX).toDouble();

  for (final object in objects) {
    object['x'] = _clean((object['x'] as num).toDouble() + dx);
  }

  final challenge = stage['challenge'];
  if (challenge is Map<String, dynamic>) {
    final star = challenge['collectible_star'];
    if (star is Map<String, dynamic>) {
      star['x'] = _clean((star['x'] as num).toDouble() + dx);
    }
  }
}

Map<String, dynamic> _challengeFor(Map<String, dynamic> stage) {
  final solutionCount = (stage['solution'] as List<dynamic>).length;
  final existing = stage['challenge'];
  final result = <String, dynamic>{'part_limit': solutionCount};
  if (existing is Map<String, dynamic> &&
      existing['collectible_star'] is Map<String, dynamic>) {
    result['collectible_star'] = existing['collectible_star'];
  }
  return result;
}

/// A part limit only becomes a real player choice when the tray offers more
/// than the reference solution needs. Give each mastery remix one safe spare
/// of an already-introduced part; clearing remains open-ended, while the
/// second star rewards the concise machine.
void _offerSparePart(Map<String, dynamic> stage) {
  final tray = stage['tray'] as List<dynamic>;
  final available = tray
      .cast<Map<String, dynamic>>()
      .map((entry) => entry['count'] as int)
      .fold(0, (a, b) => a + b);
  final needed = (stage['solution'] as List<dynamic>).length;
  if (available > needed) return;

  final first = tray.first as Map<String, dynamic>;
  first['count'] = (first['count'] as int) + 1;
}

void _applyPresentationHooks(int world, int index, Map<String, dynamic> stage) {
  const chainStages = {
    'w1_s14',
    'w1_s15',
    'w2_s18',
    'w3_s15',
    'w3_s20',
    'w4_s19',
    'w4_s20',
  };
  if (chainStages.contains(_stageId(world, index))) {
    stage['feature'] = 'chain_reaction';
  }

  final id = _stageId(world, index);
  if (id == 'w2_s19' || id == 'w2_s20') {
    stage['prediction'] = {'answer': 'metal_ball'};
  } else if (id == 'w4_s12') {
    stage['prediction'] = {'answer': 'rubber_ball'};
  }
}

num _clean(double value) {
  final rounded = double.parse(value.toStringAsFixed(2));
  return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
}

import 'dart:convert';
import 'dart:io';

import 'registry.dart';
import 'sim_world.dart';
import 'stage_data.dart';

/// x±0.05m, angle±2° applied to every solution placement at once (same
/// offset for every placement in one run). 3 fixed variants - deterministic,
/// no RNG - a solution must clear with all of them (plus the untouched
/// original) to guard against knife-edge placements a finger can't
/// reproduce. y is never jittered (contract only specifies x/angle).
const List<(double dx, double dAngleDeg)> jitterVariants = [
  (0.05, 2.0),
  (-0.05, -2.0),
  (0.05, -2.0),
];

/// One stage's validation outcome. [stepsToClear] is the original
/// (un-jittered) solution's step count; null whenever that run itself didn't
/// clear (or the file never parsed). [jitterStepsToClear] mirrors
/// [jitterVariants] 1:1 (null entries = that variant didn't clear).
class StageValidation {
  const StageValidation({
    required this.id,
    required this.ok,
    required this.failReason,
    required this.stepsToClear,
    required this.jitterStepsToClear,
  });

  final String id;
  final bool ok;
  final String? failReason;
  final int? stepsToClear;
  final List<int?> jitterStepsToClear;
}

/// Report for a whole `assets/stages`-shaped directory.
class ValidationReport {
  const ValidationReport({
    required this.stages,
    required this.missingFiles,
    required this.extraFiles,
  });

  /// One entry per [stageOrder] id that has a matching file, in
  /// [stageOrder] order.
  final List<StageValidation> stages;

  /// stageOrder ids with no `<id>.json` file in the directory.
  final List<String> missingFiles;

  /// `<id>.json` files present whose id isn't in stageOrder.
  final List<String> extraFiles;

  bool get ok =>
      missingFiles.isEmpty && extraFiles.isEmpty && stages.every((s) => s.ok);
}

/// Validates every stage in [dir] against [stageOrder]: the file set must
/// match exactly (both directions), every file must parse as [StageData],
/// and each stage's solution must clear within [maxSteps] both as authored
/// and under all [jitterVariants].
ValidationReport validateAllStages(String dir, {int maxSteps = 1800}) {
  final directory = Directory(dir);
  final fileIds = directory.existsSync()
      ? directory
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.endsWith('.json'))
          .map((name) => name.substring(0, name.length - '.json'.length))
          .toSet()
      : <String>{};
  final orderSet = stageOrder.toSet();

  final missingFiles = [
    for (final id in stageOrder)
      if (!fileIds.contains(id)) id
  ];
  final extraFiles = [
    for (final id in fileIds)
      if (!orderSet.contains(id)) id
  ]..sort();

  final stages = [
    for (final id in stageOrder)
      if (fileIds.contains(id)) _validateOne(dir, id, maxSteps)
  ];

  return ValidationReport(
    stages: stages,
    missingFiles: missingFiles,
    extraFiles: extraFiles,
  );
}

StageValidation _validateOne(String dir, String id, int maxSteps) {
  final StageData data;
  try {
    final raw = File('$dir/$id.json').readAsStringSync();
    data = StageData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    return StageValidation(
      id: id,
      ok: false,
      failReason: 'parse failed: $e',
      stepsToClear: null,
      jitterStepsToClear: const [],
    );
  }

  final stepsToClear = _runToClear(data, data.solution, maxSteps);
  final jitterSteps = [
    for (final (dx, dAngle) in jitterVariants)
      _runToClear(data, _jitter(data.solution, dx, dAngle), maxSteps)
  ];

  String? failReason;
  if (stepsToClear == null) {
    failReason = 'solution did not clear within $maxSteps steps';
  } else {
    final failedIdx = jitterSteps.indexWhere((s) => s == null);
    if (failedIdx != -1) {
      final (dx, dAngle) = jitterVariants[failedIdx];
      failReason = 'jitter (dx=$dx, dAngle=$dAngle) did not clear within '
          '$maxSteps steps';
    }
  }

  return StageValidation(
    id: id,
    ok: stepsToClear != null && jitterSteps.every((s) => s != null),
    failReason: failReason,
    stepsToClear: stepsToClear,
    jitterStepsToClear: jitterSteps,
  );
}

List<Placement> _jitter(List<Placement> solution, double dx, double dAngle) => [
      for (final p in solution)
        Placement(
          type: p.type,
          x: p.x + dx,
          y: p.y,
          angleDeg: p.angleDeg + dAngle,
        )
    ];

/// Steps a fresh [SimWorld] until cleared or [maxSteps] reached; returns the
/// step count at clear, or null if it never cleared. Builds its own loop
/// (rather than [SimWorld.verify]) because it needs the step count, which
/// verify() discards along with the SimWorld instance.
int? _runToClear(StageData stage, List<Placement> placements, int maxSteps) {
  final w = SimWorld(stage, placements);
  while (!w.cleared && w.stepCount < maxSteps) {
    w.step();
  }
  return w.cleared ? w.stepCount : null;
}

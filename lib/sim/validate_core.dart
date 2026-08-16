import 'dart:convert';
import 'dart:io';

import 'catalog.dart';
import 'placement_rules.dart';
import 'registry.dart';
import 'sim_world.dart';
import 'stage_data.dart';

/// x±0.05m applied to every solution placement and angle±2° applied only to
/// parts the editor actually lets the player rotate (plank/fan). 3 fixed
/// deterministic variants guard against knife-edge finger drops. Gears,
/// seesaws and trampolines keep angle 0 because the player cannot rotate them.
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

/// Validates every stage in [dir] against [stageOrder]: (a) the file set
/// must match exactly (both directions), (b) every file must parse as
/// [StageData], (c) each stage's solution must clear within [maxSteps] both
/// as authored and under all [jitterVariants], (d) the stage must NOT clear
/// with an empty placement list (a self-solving stage isn't a puzzle), (e)
/// the solution must be PLACEABLE under the game's own canPlaceAt rules (see
/// [solutionPlacementIssue]) and fit inside the stage's own tray counts - a
/// solution that only clears because the JSON put a part somewhere a player
/// could never actually drop it isn't a real solution, and (f) every preset
/// object must be VISIBLE above the bottom tray bar in edit mode (see
/// [_visibilityIssue]) - a goal object the player can never see isn't a real
/// puzzle either, even if the physics clears fine. (e) and (f) are checked
/// before any physics runs (cheapest checks, and the most fundamental - an
/// unplaceable or invisible solution isn't worth 1800 simulated steps).
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
      if (!fileIds.contains(id)) id,
  ];
  final extraFiles = [
    for (final id in fileIds)
      if (!orderSet.contains(id)) id,
  ]..sort();

  final stages = [
    for (final id in stageOrder)
      if (fileIds.contains(id)) _validateOne(dir, id, maxSteps),
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

  if (data.id != id) {
    return StageValidation(
      id: id,
      ok: false,
      failReason:
          'filename/id mismatch: $id.json declares id "${data.id}" '
          '(copy-paste 흔적 의심)',
      stepsToClear: null,
      jitterStepsToClear: const [],
    );
  }

  final placementIssue = _placementIssue(data);
  if (placementIssue != null) {
    return StageValidation(
      id: id,
      ok: false,
      failReason: placementIssue,
      stepsToClear: null,
      jitterStepsToClear: const [],
    );
  }

  final visibilityIssue = _visibilityIssue(data);
  if (visibilityIssue != null) {
    return StageValidation(
      id: id,
      ok: false,
      failReason: visibilityIssue,
      stepsToClear: null,
      jitterStepsToClear: const [],
    );
  }

  final stepsToClear = _runToClear(data, data.solution, maxSteps);
  final jitterSteps = [
    for (final (dx, dAngle) in jitterVariants)
      _runToClear(data, _jitter(data.solution, dx, dAngle), maxSteps),
  ];
  // Rule (d): a stage that clears with nothing placed isn't a puzzle. Only
  // worth checking once the real solution already clears - otherwise the
  // solution failure above is already the reason to report.
  final selfSolving =
      stepsToClear != null &&
      SimWorld.verify(data, const [], maxSteps: maxSteps);

  String? failReason;
  if (stepsToClear == null) {
    failReason = 'solution did not clear within $maxSteps steps';
  } else {
    final failedIdx = jitterSteps.indexWhere((s) => s == null);
    if (failedIdx != -1) {
      final (dx, dAngle) = jitterVariants[failedIdx];
      failReason =
          'jitter (dx=$dx, dAngle=$dAngle) did not clear within '
          '$maxSteps steps';
    } else if (selfSolving) {
      failReason =
          'self-solving: clears with no placements at all - not '
          'a puzzle';
    }
  }

  return StageValidation(
    id: id,
    ok:
        stepsToClear != null &&
        jitterSteps.every((s) => s != null) &&
        !selfSolving,
    failReason: failReason,
    stepsToClear: stepsToClear,
    jitterStepsToClear: jitterSteps,
  );
}

/// Rule (e) - null if [data]'s solution is fine, else the first problem
/// found: either it uses more of some part type than [StageData.tray]
/// provides, or [solutionPlacementIssue] rejects it (out of bounds,
/// overlaps a preset/earlier solution part, or a gear-family part isn't
/// authored at its snapped position).
String? _placementIssue(StageData data) {
  final trayCounts = <PartType, int>{};
  for (final t in data.tray) {
    trayCounts[t.type] = t.count;
  }
  final used = <PartType, int>{};
  for (final p in data.solution) {
    used[p.type] = (used[p.type] ?? 0) + 1;
  }
  for (final entry in used.entries) {
    final allowed = trayCounts[entry.key] ?? 0;
    if (entry.value > allowed) {
      return 'solution uses ${entry.value}x ${jsonIdOf(entry.key)} but tray '
          'only has $allowed';
    }
  }
  return solutionPlacementIssue(data.preset, data.solution);
}

/// Rule (f) - null if every entry of [data.preset] is visible above the
/// bottom tray bar in edit mode, else a reason for the first hidden one.
/// Reuses [boxForPreset] (same footprint placement legality already checks
/// presets against) so this can never drift from what a player actually
/// sees/drops around - basket/button's half-heights (0.36/0.11) come from
/// there too, mirroring the hand-fitted footprints [SimWorld] itself builds
/// (`_buildBasket`/`_buildButton`), and every catalog part type's
/// half-height comes straight from [Catalog.of] (radius, else h/2).
///
/// Platforms are the one exception: only their walking SURFACE (top) needs
/// to clear the line, not the whole slab - a platform's floor may legally
/// dip under the bar. Its footprint is the raw half-thickness (0.2, matching
/// `_buildPlatform`'s fixture) below [PresetObject.y], not [boxForPreset]'s
/// rotated box (platforms can be steep ramps; the walking surface is still
/// what a player needs to see, not the rotated AABB's lowest corner).
String? _visibilityIssue(StageData data) {
  for (final p in data.preset) {
    if (p.type == 'platform') {
      final surfaceY = p.y - 0.2;
      if (surfaceY > kTrayVisibleMaxY) {
        return 'hidden behind tray: platform y=${p.y}';
      }
      continue;
    }
    final box = boxForPreset(p);
    final bottomY = box.cy + box.halfY;
    if (bottomY > kTrayVisibleMaxY) {
      return 'hidden behind tray: ${p.type} y=${p.y}';
    }
  }
  return null;
}

List<Placement> _jitter(List<Placement> solution, double dx, double dAngle) => [
  for (final p in solution)
    Placement(
      type: p.type,
      x: p.x + dx,
      y: p.y,
      angleDeg: p.angleDeg + (Catalog.of(p.type).rotatable ? dAngle : 0),
    ),
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

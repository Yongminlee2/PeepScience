import 'dart:convert';
import 'dart:io';

import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/placement_rules.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/sim_world.dart';
import 'package:piyak_science/sim/stage_data.dart';

/// Searches the mastery half for obvious one-part bypasses at a deterministic
/// set of goal-adjacent, payload-adjacent and coarse whole-field placements.
/// This complements (rather than replaces) the exact-solution removal tests.
void main(List<String> args) {
  var shortcutCount = 0;
  final ids = args.isEmpty ? stageOrder.where(_isExpertId) : args;
  for (final id in ids) {
    if (!_isExpertId(id) || !stageOrder.contains(id)) {
      stderr.writeln('Unknown expert stage id: $id');
      exitCode = 2;
      return;
    }
    final stage = StageData.fromJson(
      jsonDecode(File('assets/stages/$id.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final presetBoxes = [for (final p in stage.preset) boxForPreset(p)];
    final anchors = <(double, double)>{
      for (final p in stage.preset) (p.x, p.y),
      for (var x = 1.0; x <= 15; x += 2) (x, 2.0),
      for (var x = 1.0; x <= 15; x += 2) (x, 4.5),
      for (var x = 1.0; x <= 15; x += 2) (x, 7.0),
    };
    final types = stage.tray.map((entry) => entry.type).toSet();
    var found = false;
    for (final type in types) {
      final angles = Catalog.of(type).rotatable
          ? const [-180.0, -135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0]
          : const [0.0];
      for (final anchor in anchors) {
        for (final dx in const [-2.0, -1, -0.5, 0, 0.5, 1, 2]) {
          for (final dy in const [-1.0, -0.5, 0, 0.5, 1.0]) {
            for (final angle in angles) {
              final rawX = anchor.$1 + dx;
              final rawY = anchor.$2 + dy;
              final (x, y) = snapGearPosition(presetBoxes, type, rawX, rawY);
              if (!canPlaceAt(presetBoxes, type, x, y, angle)) continue;
              final placement = Placement(
                type: type,
                x: x,
                y: y,
                angleDeg: angle,
              );
              if (!SimWorld.verify(stage, [placement], maxSteps: 700)) {
                continue;
              }
              stdout.writeln(
                'SHORTCUT $id ${jsonIdOf(type)} '
                '@ ${x.toStringAsFixed(2)},${y.toStringAsFixed(2)} '
                'angle=${angle.toStringAsFixed(0)}',
              );
              shortcutCount++;
              found = true;
              break;
            }
            if (found) break;
          }
          if (found) break;
        }
        if (found) break;
      }
      if (found) break;
    }
  }

  if (shortcutCount > 0) {
    stderr.writeln('RESULT: $shortcutCount expert stage shortcut(s) found');
    exitCode = 1;
  } else {
    stdout.writeln('RESULT: no sampled one-part expert shortcut');
  }
}

bool _isExpertId(String id) => int.parse(id.substring(id.length - 2)) >= 11;

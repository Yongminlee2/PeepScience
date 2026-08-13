import 'dart:math';

import 'catalog.dart';
import 'stage_data.dart';

/// Placement field bounds, in world meters (a part's own CENTER must land
/// inside). Shared contract: x 0.3-15.7, y 0.3-7.3 - the tray HUD occupies
/// the screen strip below y=7.3 (world is 9m tall). Presets are NOT bound by
/// this (level terrain/goal objects can sit anywhere, including off-screen -
/// docs/이어서-작업하기.md 2절) - only solution/player placements are.
const double kFieldMinX = 0.3;
const double kFieldMaxX = 15.7;
const double kFieldMinY = 0.3;
const double kFieldMaxY = 7.3;

/// Validator rule (f) bound, in world meters: a preset's visible footprint
/// must sit above this line. The tray HUD (hud.dart TrayBar, barHeight=150
/// on the 1600x900 logical screen PiyakGame renders at) covers screen y >
/// 750px; at the fixed 16x9m-world/1600x900px camera that's world y > 7.5.
/// 7.45 leaves a hair of margin below the true edge. Distinct from
/// [kFieldMaxY] (7.3), which bounds where a solution placement's CENTER may
/// be dropped - this bounds where a PRESET's rendered edge may sit.
const double kTrayVisibleMaxY = 7.45;

/// Minimum gap (meters) required between a candidate's AABB and any existing
/// preset/placement AABB - except gear-family pairs, which are allowed to
/// overlap because they mesh instead (see [snapGearPosition]).
const double kOverlapMargin = 0.02;

/// Gear-family center-distance snap target: r1+r2 minus this slack, so the
/// teeth visually interlock and the result sits safely inside SimWorld's
/// r1+r2+0.05 meshing-detection radius (shared-contract.md).
const double kGearSnapSlack = 0.03;

/// How close a drop has to land (beyond the two gears' own radii combined)
/// before it triggers the snap at all - a generous "magnet" range for a
/// sloppy drop.
const double kGearSnapCatchRange = 0.15;

bool isGearFamily(PartType t) =>
    t == PartType.motorGear || t == PartType.gear || t == PartType.paddleGear;

/// A conservative axis-aligned footprint for overlap checks: ([cx],[cy]) +
/// ([halfX],[halfY]) half-extents in meters. [gearRadius] is the catalog
/// gear radius (not the AABB half-extent) for gear-family members, used by
/// the snap-distance math in [snapGearPosition]; null for everything else.
class PlacementBox {
  const PlacementBox(this.cx, this.cy, this.halfX, this.halfY,
      {this.gearRadius});

  final double cx;
  final double cy;
  final double halfX;
  final double halfY;
  final double? gearRadius;
  bool get isGearFamily => gearRadius != null;
}

/// Conservative rotated half-extents (meters) for a [hw]x[hh] (half-width x
/// half-height) box rotated by [angleRad].
(double, double) rotatedHalfExtents(double hw, double hh, double angleRad) {
  final c = cos(angleRad).abs();
  final sn = sin(angleRad).abs();
  return (hw * c + hh * sn, hw * sn + hh * c);
}

/// [PlacementBox] for a catalog part [type] centered at ([cx],[cy]) rotated
/// [angleDeg].
PlacementBox boxForPart(PartType type, double cx, double cy, double angleDeg) {
  final s = Catalog.of(type);
  final angleRad = angleDeg * pi / 180;
  final double halfX, halfY;
  if (s.radius != null && s.w != null) {
    // paddleGear: union of the circular gear body and its paddle bar.
    final (bx, by) = rotatedHalfExtents(s.w! / 2, s.h! / 2, angleRad);
    halfX = max(s.radius!, bx);
    halfY = max(s.radius!, by);
  } else if (s.radius != null) {
    halfX = s.radius!;
    halfY = s.radius!;
  } else {
    (halfX, halfY) = rotatedHalfExtents(s.w! / 2, s.h! / 2, angleRad);
  }
  return PlacementBox(cx, cy, halfX, halfY,
      gearRadius: isGearFamily(type) ? s.radius : null);
}

/// [PlacementBox] for a `stage.preset` entry - platform/basket/button get
/// their own hand-fitted footprints (matching [PartView]'s art), everything
/// else is a catalog part.
PlacementBox boxForPreset(PresetObject p) {
  switch (p.type) {
    case 'platform':
      final (hx, hy) =
          rotatedHalfExtents(p.w! / 2, 0.2, p.angleDeg * pi / 180);
      return PlacementBox(p.x, p.y, hx, hy);
    case 'basket':
      // Matches PartView's basket footprint (floor + two walls envelope).
      return PlacementBox(p.x, p.y, 0.5, 0.36);
    case 'button':
      return PlacementBox(p.x, p.y, 0.4, 0.11);
    default:
      return boxForPart(partTypeFromJson(p.type), p.x, p.y, p.angleDeg);
  }
}

bool aabbOverlaps(PlacementBox a, PlacementBox b, double margin) {
  final dx = (a.cx - b.cx).abs();
  final dy = (a.cy - b.cy).abs();
  return dx < a.halfX + b.halfX + margin && dy < a.halfY + b.halfY + margin;
}

/// Reason [type] at ([x],[y]) (its own center, rotated [angleDeg]) would be
/// REJECTED against [existingBoxes] (presets + prior placements), or null if
/// the placement is legal. [canPlaceAt] is this with the reason thrown away
/// (the hot path - called every drag-update frame - only needs the bool) -
/// this is the single source of truth so the two can never drift apart.
String? placementRejectReason(Iterable<PlacementBox> existingBoxes,
    PartType type, double x, double y, double angleDeg) {
  if (x < kFieldMinX || x > kFieldMaxX || y < kFieldMinY || y > kFieldMaxY) {
    return 'out of bounds: ($x, $y) not in x:[$kFieldMinX,$kFieldMaxX] '
        'y:[$kFieldMinY,$kFieldMaxY]';
  }
  final candidate = boxForPart(type, x, y, angleDeg);
  for (final other in existingBoxes) {
    if (candidate.isGearFamily && other.isGearFamily) continue;
    if (aabbOverlaps(candidate, other, kOverlapMargin)) {
      return 'overlaps existing box at (${other.cx}, ${other.cy})';
    }
  }
  return null;
}

/// True if [type] at ([x],[y]) (its own center) can be placed there: inside
/// the field, and not overlapping (within [kOverlapMargin]) any box in
/// [existingBoxes] - except gear-family vs. gear-family pairs, which are
/// allowed to overlap so they can mesh. [angleDeg] only matters for the two
/// rotatable types (plank, fan).
bool canPlaceAt(Iterable<PlacementBox> existingBoxes, PartType type, double x,
        double y, double angleDeg) =>
    placementRejectReason(existingBoxes, type, x, y, angleDeg) == null;

/// If [type] is gear-family and a same-family neighbor in [existingBoxes]
/// exists within r1+r2+[kGearSnapCatchRange] of ([rawX],[rawY]), returns the
/// point at exactly r1+r2-[kGearSnapSlack] from that neighbor's center,
/// along the neighbor->raw direction. Otherwise (including for non-gear
/// types, or no neighbor in range) returns ([rawX],[rawY]) unchanged.
(double, double) snapGearPosition(Iterable<PlacementBox> existingBoxes,
    PartType type, double rawX, double rawY) {
  if (!isGearFamily(type)) return (rawX, rawY);
  final r1 = Catalog.of(type).radius!;
  PlacementBox? nearest;
  var nearestDist = double.infinity;
  for (final other in existingBoxes) {
    if (!other.isGearFamily) continue;
    final d = sqrt(pow(other.cx - rawX, 2) + pow(other.cy - rawY, 2));
    if (d < nearestDist) {
      nearestDist = d;
      nearest = other;
    }
  }
  if (nearest == null ||
      nearestDist > r1 + nearest.gearRadius! + kGearSnapCatchRange) {
    return (rawX, rawY);
  }
  final targetDist = r1 + nearest.gearRadius! - kGearSnapSlack;
  final double dirX, dirY;
  if (nearestDist < 1e-6) {
    dirX = 1;
    dirY = 0;
  } else {
    dirX = (rawX - nearest.cx) / nearestDist;
    dirY = (rawY - nearest.cy) / nearestDist;
  }
  return (nearest.cx + dirX * targetDist, nearest.cy + dirY * targetDist);
}

/// Rule (e): checks that every entry of [solution] is PLACEABLE in authored
/// order against [preset] - each one run through bounds -> gear-snap ->
/// overlap vs. (presets + every solution entry before it), exactly what a
/// player dragging them onto the field one at a time from the tray would
/// hit (see [canPlaceAt]/[snapGearPosition]). Also requires gear-family
/// entries to already be authored at their snapped position (within 1cm) -
/// otherwise the game would silently relocate them, and the authored JSON
/// would no longer describe what actually gets built. Returns null if the
/// whole solution is legal, else the first problem found.
///
/// Does NOT check whether the solution physically clears (see
/// `SimWorld.verify`) or whether it fits the stage's tray counts -
/// validate_core.dart's stage-file validator layers both of those on top.
String? solutionPlacementIssue(
    List<PresetObject> preset, List<Placement> solution) {
  final boxes = [for (final p in preset) boxForPreset(p)];
  for (var i = 0; i < solution.length; i++) {
    final p = solution[i];
    final (sx, sy) = snapGearPosition(boxes, p.type, p.x, p.y);
    final drift = sqrt(pow(sx - p.x, 2) + pow(sy - p.y, 2));
    if (drift > 0.01) {
      return 'solution[$i] (${jsonIdOf(p.type)} at (${p.x}, ${p.y})) is '
          '${drift.toStringAsFixed(3)}m from its gear-snapped position '
          '(${sx.toStringAsFixed(2)}, ${sy.toStringAsFixed(2)}) - author it '
          'at the snapped spot';
    }
    final reason = placementRejectReason(boxes, p.type, sx, sy, p.angleDeg);
    if (reason != null) {
      return 'solution[$i] (${jsonIdOf(p.type)} at (${p.x}, ${p.y})) '
          'rejected by placement rules: $reason';
    }
    boxes.add(boxForPart(p.type, sx, sy, p.angleDeg));
  }
  return null;
}

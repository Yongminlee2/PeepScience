import 'dart:math';

import 'package:flame/components.dart';

import '../sim/catalog.dart';
import '../sim/stage_data.dart';
import 'piyak_game.dart';

/// Placement field bounds, in world meters (the part's own CENTER must land
/// inside). Shared contract: x 0.3-15.7, y 0.3-7.3 - the tray HUD occupies
/// the screen strip below y=7.3 (world is 9m tall).
const double kFieldMinX = 0.3;
const double kFieldMaxX = 15.7;
const double kFieldMinY = 0.3;
const double kFieldMaxY = 7.3;

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

bool _isGearFamily(PartType t) =>
    t == PartType.motorGear || t == PartType.gear || t == PartType.paddleGear;

/// World-pixel position (matches `PartView`/`Placement` coordinates, i.e.
/// meters * `kPpm`) for a point given in the game canvas's coordinate space
/// (e.g. `DragStartEvent.canvasPosition` / `DragUpdateEvent.canvasEndPosition`).
///
/// Goes through both the viewport (letterbox/scale) and viewfinder (pan/
/// zoom) transforms via `CameraComponent.globalToLocal`, rather than
/// hard-coding today's identity viewfinder - verified against the installed
/// flame 1.38.0 source (lib/src/camera/camera_component.dart,
/// viewport.dart, viewfinder.dart, transform2d.dart: none of the
/// globalToLocal chain mutates its input point when `output` isn't passed).
Vector2 canvasToWorldPx(PiyakGame game, Vector2 canvasPoint) =>
    game.camera.globalToLocal(canvasPoint);

/// True if [type] at [worldPos] (its own center) can be placed there:
/// inside the field, and not overlapping (within [kOverlapMargin]) any
/// existing stage.preset or game.placements footprint - except gear-family
/// vs. gear-family pairs, which are allowed to overlap so they can mesh.
/// [angleDeg] only matters for the two rotatable types (plank, fan).
///
/// Reusable: Task 8 (moving an existing part) and Task 12 (stage editor)
/// call this too.
bool canPlaceAt(
    PiyakGame game, PartType type, Vector2 worldPos, double angleDeg) {
  if (worldPos.x < kFieldMinX ||
      worldPos.x > kFieldMaxX ||
      worldPos.y < kFieldMinY ||
      worldPos.y > kFieldMaxY) {
    return false;
  }
  final candidate = _boxForPart(type, worldPos, angleDeg);
  for (final other in _existingBoxes(game)) {
    if (candidate.isGearFamily && other.isGearFamily) continue;
    if (_aabbOverlaps(candidate, other, kOverlapMargin)) return false;
  }
  return true;
}

/// If [type] is gear-family and a same-family preset/placement neighbor
/// exists within r1+r2+[kGearSnapCatchRange] of [rawWorldPos], returns the
/// point at exactly r1+r2-[kGearSnapSlack] from that neighbor's center,
/// along the neighbor->rawWorldPos direction. Otherwise (including for
/// non-gear types, or no neighbor in range) returns [rawWorldPos] unchanged.
Vector2 snapGearPosition(PiyakGame game, PartType type, Vector2 rawWorldPos) {
  if (!_isGearFamily(type)) return rawWorldPos;
  final r1 = Catalog.of(type).radius!;
  _Box? nearest;
  var nearestDist = double.infinity;
  for (final other in _existingBoxes(game)) {
    if (!other.isGearFamily) continue;
    final d = (other.center - rawWorldPos).length;
    if (d < nearestDist) {
      nearestDist = d;
      nearest = other;
    }
  }
  if (nearest == null ||
      nearestDist > r1 + nearest.gearRadius! + kGearSnapCatchRange) {
    return rawWorldPos;
  }
  final targetDist = r1 + nearest.gearRadius! - kGearSnapSlack;
  final dir = nearestDist < 1e-6
      ? Vector2(1, 0)
      : (rawWorldPos - nearest.center) / nearestDist;
  return nearest.center + dir * targetDist;
}

/// Resolves a raw drop point into the actual landing position (snap-adjusted
/// for gear-family types, see [snapGearPosition]) and whether that position
/// is a legal placement (see [canPlaceAt]). Used for both the live
/// drag-ghost preview and the real drop, so the ghost always shows exactly
/// what dropping right now would do.
({Vector2 pos, bool valid}) resolveDrop(
    PiyakGame game, PartType type, Vector2 rawWorldPos) {
  final pos = snapGearPosition(game, type, rawWorldPos);
  return (pos: pos, valid: canPlaceAt(game, type, pos, 0));
}

/// A conservative axis-aligned footprint for overlap checks: [center] +
/// [half]-extents in meters. [gearRadius] is the catalog gear radius (not
/// the AABB half-extent) for gear-family members, used by the snap-distance
/// math in [snapGearPosition]; null for everything else.
class _Box {
  _Box(this.center, this.half, {this.gearRadius});
  final Vector2 center;
  final Vector2 half;
  final double? gearRadius;
  bool get isGearFamily => gearRadius != null;
}

Iterable<_Box> _existingBoxes(PiyakGame game) sync* {
  for (final p in game.stage.preset) {
    yield _boxForPreset(p);
  }
  for (final pl in game.placements) {
    yield _boxForPart(pl.type, Vector2(pl.x, pl.y), pl.angleDeg);
  }
}

_Box _boxForPreset(PresetObject p) {
  final center = Vector2(p.x, p.y);
  switch (p.type) {
    case 'platform':
      return _Box(
          center, _rotatedHalfExtents(p.w! / 2, 0.2, p.angleDeg * pi / 180));
    case 'basket':
      // Matches PartView's basket footprint (floor + two walls envelope).
      return _Box(center, Vector2(0.5, 0.36));
    case 'button':
      return _Box(center, Vector2(0.4, 0.11));
    default:
      return _boxForPart(partTypeFromJson(p.type), center, p.angleDeg);
  }
}

_Box _boxForPart(PartType type, Vector2 center, double angleDeg) {
  final s = Catalog.of(type);
  final angleRad = angleDeg * pi / 180;
  final Vector2 half;
  if (s.radius != null && s.w != null) {
    // paddleGear: union of the circular gear body and its paddle bar.
    final boxHalf = _rotatedHalfExtents(s.w! / 2, s.h! / 2, angleRad);
    half = Vector2(max(s.radius!, boxHalf.x), max(s.radius!, boxHalf.y));
  } else if (s.radius != null) {
    half = Vector2.all(s.radius!);
  } else {
    half = _rotatedHalfExtents(s.w! / 2, s.h! / 2, angleRad);
  }
  return _Box(center, half, gearRadius: _isGearFamily(type) ? s.radius : null);
}

Vector2 _rotatedHalfExtents(double hw, double hh, double angleRad) {
  final c = cos(angleRad).abs();
  final sn = sin(angleRad).abs();
  return Vector2(hw * c + hh * sn, hw * sn + hh * c);
}

bool _aabbOverlaps(_Box a, _Box b, double margin) {
  final dx = (a.center.x - b.center.x).abs();
  final dy = (a.center.y - b.center.y).abs();
  return dx < a.half.x + b.half.x + margin && dy < a.half.y + b.half.y + margin;
}

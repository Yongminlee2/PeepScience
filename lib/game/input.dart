import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/widgets.dart'
    show Canvas, Color, Offset, Paint, PaintingStyle;

import '../services/sound.dart';
import '../sim/catalog.dart';
import '../sim/placement_rules.dart' as rules;
import '../sim/stage_data.dart';
import 'part_view.dart' show kPpm;
import 'piyak_game.dart';

export '../sim/placement_rules.dart'
    show kFieldMinX, kFieldMaxX, kFieldMinY, kFieldMaxY;

/// World-pixel position (matches `PartView`/`Placement` coordinates, i.e.
/// meters * `kPpm`) for a point given in the game canvas's coordinate space
/// (e.g. `TapDownEvent.canvasPosition`, `DragStartEvent.canvasPosition`, or
/// a canvas position a caller has otherwise reconstructed - see
/// hud.dart's and this file's own onDragUpdate doc comments for why a raw
/// `DragUpdateEvent.canvasStartPosition`/`canvasEndPosition` isn't always
/// one of those).
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
/// inside the field, and not overlapping (within [rules.kOverlapMargin])
/// any existing stage.preset or game.placements footprint - except
/// gear-family vs. gear-family pairs, which are allowed to overlap so they
/// can mesh. [angleDeg] only matters for the two rotatable types (plank,
/// fan). Thin adapter over the pure math in sim/placement_rules.dart (also
/// the validator's and the editor's rule (e) - one source of truth for what
/// "legal" means).
///
/// [excludeIndex], when set, skips `game.placements[excludeIndex]` itself -
/// Task 8's rotate handle uses this to validate a placement's NEW angle
/// against every OTHER part, without it always colliding with its own old
/// footprint.
///
/// Reusable: Task 8 (moving an existing part) and Task 12 (stage editor)
/// call this too.
bool canPlaceAt(
    PiyakGame game, PartType type, Vector2 worldPos, double angleDeg,
    {int? excludeIndex}) {
  return rules.canPlaceAt(_existingBoxes(game, excludeIndex: excludeIndex),
      type, worldPos.x, worldPos.y, angleDeg);
}

/// If [type] is gear-family and a same-family preset/placement neighbor
/// exists within catch range of [rawWorldPos], returns the snapped landing
/// point; otherwise returns [rawWorldPos] unchanged. See
/// sim/placement_rules.dart's `snapGearPosition` for the actual math.
Vector2 snapGearPosition(PiyakGame game, PartType type, Vector2 rawWorldPos) {
  final (x, y) = rules.snapGearPosition(
      _existingBoxes(game), type, rawWorldPos.x, rawWorldPos.y);
  return Vector2(x, y);
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

/// Every existing footprint (stage presets, then live placements in order)
/// as the pure [rules.PlacementBox] type - the one place this file bridges
/// PiyakGame's Flutter/Flame-flavored state into sim/placement_rules.dart's
/// plain-Dart inputs.
Iterable<rules.PlacementBox> _existingBoxes(PiyakGame game,
    {int? excludeIndex}) sync* {
  for (final p in game.stage.preset) {
    yield rules.boxForPreset(p);
  }
  for (var i = 0; i < game.placements.length; i++) {
    if (i == excludeIndex) continue;
    final pl = game.placements[i];
    yield rules.boxForPart(pl.type, pl.x, pl.y, pl.angleDeg);
  }
}

// -----------------------------------------------------------------------
// Task 8: select / rotate / delete an already-placed part.
//
// All hit-testing below is manual (world-space math reusing the same
// sim/placement_rules.dart boxes canPlaceAt uses) rather than giving the
// ring/handle/X their own TapCallbacks/DragCallbacks components. PiyakGame
// itself mixes in TapCallbacks/DragCallbacks (see piyak_game.dart) and,
// being the root component, is the LAST candidate flame's dispatcher checks
// for any given pointer (every descendant is matched first - see flame's
// Component.componentsAtLocation) - so this never steals events from
// hud.dart's per-slot tray drags. TapUpEvent.canvasPosition and
// DragStartEvent.canvasPosition are computed once per event independent of
// which component ends up receiving it (flame's
// PositionEvent/DisplacementEvent), so reading them here is exactly as
// correct as hud.dart's own identical usage; DragUpdateEvent needs the
// canvasDelta-accumulation dance documented on handleEditDragUpdate below
// instead, for the same reason hud.dart's onDragUpdate now does too.
//
// Selection/deletion react to onTapUp, not onTapDown - see
// handleEditTapUp's own doc comment for why (short version: onTapDown fires
// speculatively for every touch, tap or drag alike).

/// Extra visual margin (meters) added to a placed part's own footprint to
/// get its selection ring radius.
const double kSelectionRingPadding = 0.18;

/// Fixed world-space offset (meters, straight up i.e. smaller y) from a
/// placement's center to its delete-X button center. Shared contract:
/// "삭제 X는 부품 위 0.6m" - unlike the rotate handle, this does NOT turn
/// with the part's own angle.
const double kDeleteButtonOffsetM = 0.6;

/// Hit-test radius (meters) for the delete-X button.
const double kDeleteHitRadiusM = 0.28;

/// Hit-test radius (meters) for the rotate-handle knob.
const double kHandleHitRadiusM = 0.24;

/// Radius (meters) of the selection ring drawn around a placed part: the
/// smallest circle centered on the part that encloses its footprint at ANY
/// rotation (so the ring itself never has to rotate), plus
/// [kSelectionRingPadding]. Exposed for test/game/edit_test.dart and
/// [SelectionOverlay].
double selectionRingRadiusM(PartType type) {
  final s = Catalog.of(type);
  var footprint = s.radius ?? 0.0;
  if (s.w != null) {
    footprint = max(footprint, sqrt(pow(s.w! / 2, 2) + pow(s.h! / 2, 2)));
  }
  return footprint + kSelectionRingPadding;
}

/// World-space position of [p]'s rotate-handle knob: on the selection
/// ring's edge, in the direction of the part's own current
/// [Placement.angleDeg] (0 deg = straight along +x - the same rotation
/// convention PartView's `angle` and placement_rules.dart's `boxForPart`'s
/// `angleRad` already use, so the handle visibly orbits in sync as the part
/// turns).
/// Exposed for test/game/edit_test.dart to locate the drag-start point.
Vector2 rotateHandleWorldPos(Placement p) {
  final r = selectionRingRadiusM(p.type);
  final rad = p.angleDeg * pi / 180;
  return Vector2(p.x + cos(rad) * r, p.y + sin(rad) * r);
}

/// World-space center of [p]'s delete-X button: [kDeleteButtonOffsetM]
/// above the part, clamped so its hit circle never crosses the top of the
/// visible field (world y=0). A straight `p.y - offset` would push the
/// WHOLE hit circle off-canvas - and therefore permanently untappable -
/// for any part placed near the top edge: y=[kFieldMinY] (0.3) is a legal
/// placement, and 0.3-0.6=-0.3 is not on screen at all. The single shared
/// spot both [handleEditTapUp]'s hit-test and [SelectionOverlay]'s render
/// call, so the tappable and visible positions can never drift apart.
Vector2 deleteButtonWorldPos(Placement p) =>
    Vector2(p.x, max(p.y - kDeleteButtonOffsetM, kDeleteHitRadiusM));

/// Index of the topmost `game.placements` entry whose AABB (the same
/// conservative box canPlaceAt/placement_rules.dart's `boxForPart` use)
/// contains [worldPos], or null. Iterates back-to-front so the
/// most-recently-placed part wins on overlap. Only [PiyakGame.placements]
/// is selectable - never
/// `game.stage.preset` (level terrain/goal objects aren't player-editable).
int? _placementIndexAt(PiyakGame game, Vector2 worldPos) {
  for (var i = game.placements.length - 1; i >= 0; i--) {
    final p = game.placements[i];
    final box = rules.boxForPart(p.type, p.x, p.y, p.angleDeg);
    if ((worldPos.x - box.cx).abs() <= box.halfX &&
        (worldPos.y - box.cy).abs() <= box.halfY) {
      return i;
    }
  }
  return null;
}

/// PiyakGame.onTapUp delegates here - NOT onTapDown, deliberately: flame's
/// MultiTapGestureRecognizer fires onTapDown speculatively for EVERY
/// pointer-down (tap or drag alike, same as Flutter's stock tap recognizers
/// firing their own "down" callback optimistically to support instant
/// pressed-states) and only later either confirms it (onTapUp, if this
/// pointer resolves as a genuine tap) or retracts it (onTapCancel, if a
/// competing recognizer - here, PiyakGame's own DragCallbacks - wins the
/// gesture-arena instead). Acting on onTapDown would select/deselect BEFORE
/// a rotate-handle drag on the very same pointer got a chance to claim
/// itself in handleEditDragStart, wrongly clearing the selection out from
/// under it (confirmed empirically while building this - the drag's own
/// onDragStart always saw selectedIndex already wiped to null by then).
///
/// Priority order once a tap is confirmed: delete-X (only if something's
/// already selected) > tap-a-part (select/switch) > tap-empty-field (clear
/// selection) - matches the brief's "탭하여 다른 부품 선택 시 전환/해제".
void handleEditTapUp(PiyakGame game, TapUpEvent event) {
  if (game.mode != GameMode.edit) return;
  final worldPos = canvasToWorldPx(game, event.canvasPosition) / kPpm;
  final idx = game.selectedIndex;
  if (idx != null && idx < game.placements.length) {
    final p = game.placements[idx];
    if ((worldPos - deleteButtonWorldPos(p)).length <= kDeleteHitRadiusM) {
      // removePlacement itself nulls/adjusts selectedIndex - single choke
      // point, see its own doc comment (piyak_game.dart).
      game.removePlacement(idx);
      Sound.play(Sfx.tap); // 삭제=tap (shared-contract 트리거 표)
      return;
    }
  }
  game.selectedIndex = _placementIndexAt(game, worldPos);
}

/// PiyakGame.onDragStart delegates here. Only claims the drag (sets
/// [PiyakGame.rotatingIndex]) when a rotatable part is selected AND the
/// drag starts on its handle knob - otherwise a no-op, so any other
/// world-space drag passes through untouched (there is none today besides
/// the tray, which lives under camera.viewport and - being a descendant -
/// is always matched before PiyakGame itself ever sees the event).
void handleEditDragStart(PiyakGame game, DragStartEvent event) {
  if (game.mode != GameMode.edit) return;
  final idx = game.selectedIndex;
  if (idx == null || idx >= game.placements.length) return;
  final p = game.placements[idx];
  if (!Catalog.of(p.type).rotatable) return;
  final worldPos = canvasToWorldPx(game, event.canvasPosition) / kPpm;
  if ((worldPos - rotateHandleWorldPos(p)).length > kHandleHitRadiusM) return;
  game.rotatingIndex = idx;
  game.rotateFallbackAngleDeg = p.angleDeg;
  game.rotateDragCanvasPos = event.canvasPosition;
}

/// PiyakGame.onDragUpdate delegates here. Live-commits the snapped angle on
/// every tick - even one that would overlap something - so the player sees
/// the part actually follow their finger; canPlaceAt is only consulted for
/// the ring's valid/invalid tint ([SelectionOverlay]) and the
/// revert-on-release check ([handleEditDragEnd]). This is the "clamp on
/// release" choice called out in task-8-brief.md (see task-8-report.md).
///
/// Tracks the pointer via [PiyakGame.rotateDragCanvasPos] + event.canvasDelta
/// rather than event.canvasStartPosition/canvasEndPosition directly - see
/// hud.dart's onDragUpdate doc comment (same fix, same root cause: PiyakGame's
/// own TapCallbacks now competes in the gesture arena for every pointer in
/// the game, which flips which of flame's two DragUpdateDetails-construction
/// paths fires for a given update).
void handleEditDragUpdate(PiyakGame game, DragUpdateEvent event) {
  final idx = game.rotatingIndex;
  final lastCanvasPos = game.rotateDragCanvasPos;
  if (idx == null || idx >= game.placements.length || lastCanvasPos == null) {
    return;
  }
  final p = game.placements[idx];
  final canvasPos = lastCanvasPos + event.canvasDelta;
  game.rotateDragCanvasPos = canvasPos;
  final worldPos = canvasToWorldPx(game, canvasPos) / kPpm;
  final rawDeg = atan2(worldPos.y - p.y, worldPos.x - p.x) * 180 / pi;
  final snapped = (rawDeg / 5).round() * 5.0;
  if (snapped != p.angleDeg) {
    game.setPlacementAngle(idx, snapped);
  }
}

/// PiyakGame.onDragEnd delegates here (a cancelled drag arrives here too,
/// via DragCallbacks' default onDragCancel -> onDragEnd forwarding):
/// reverts to [PiyakGame.rotateFallbackAngleDeg] if the drag's final angle
/// overlaps something, per canPlaceAt with the rotating part itself
/// excluded.
void handleEditDragEnd(PiyakGame game, DragEndEvent event) {
  final idx = game.rotatingIndex;
  game.rotatingIndex = null;
  game.rotateDragCanvasPos = null;
  if (idx == null || idx >= game.placements.length) return;
  final p = game.placements[idx];
  final valid = canPlaceAt(game, p.type, Vector2(p.x, p.y), p.angleDeg,
      excludeIndex: idx);
  if (!valid) {
    game.setPlacementAngle(idx, game.rotateFallbackAngleDeg);
  }
}

/// Edit-mode-only visual for [PiyakGame.selectedIndex]: a ring around the
/// selected placement, a delete-X 0.6m above it, and (only when the type is
/// rotatable - plank, fan) a rotate-handle knob on the ring's edge, tinted
/// red while a rotate drag is at an invalid angle. Purely a renderer - all
/// hit-testing lives in this section's handleEdit*() functions above, which
/// read/write PiyakGame's selection fields directly (see this section's own
/// header comment for why). Added once in PiyakGame.onLoad with a high
/// priority so it always draws on top of every PartView.
class SelectionOverlay extends Component {
  SelectionOverlay(this.game) : super(priority: 1000);

  final PiyakGame game;

  bool _visible = false;
  bool _showHandle = false;
  bool _invalid = false;
  late Offset _center;
  late double _ringRadiusPx;
  late Offset _handlePos;
  late Offset _deleteCenter;

  @override
  void update(double dt) {
    final idx = game.selectedIndex;
    if (game.mode != GameMode.edit ||
        idx == null ||
        idx >= game.placements.length) {
      _visible = false;
      return;
    }
    _visible = true;
    final p = game.placements[idx];
    _center = _px(p.x, p.y);
    _ringRadiusPx = selectionRingRadiusM(p.type) * kPpm;
    _showHandle = Catalog.of(p.type).rotatable;
    if (_showHandle) {
      final h = rotateHandleWorldPos(p);
      _handlePos = _px(h.x, h.y);
    }
    final del = deleteButtonWorldPos(p);
    _deleteCenter = _px(del.x, del.y);
    _invalid = game.rotatingIndex == idx &&
        !canPlaceAt(game, p.type, Vector2(p.x, p.y), p.angleDeg,
            excludeIndex: idx);
  }

  static Offset _px(double xM, double yM) => Offset(xM * kPpm, yM * kPpm);

  @override
  void render(Canvas canvas) {
    if (!_visible) return;
    final ringColor =
        _invalid ? const Color(0xFFE53935) : const Color(0xFF2979FF);
    canvas.drawCircle(
      _center,
      _ringRadiusPx,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    if (_showHandle) {
      canvas.drawLine(
        _center,
        _handlePos,
        Paint()
          ..color = ringColor
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
          _handlePos, 14, Paint()..color = const Color(0xFFFFC107));
      canvas.drawCircle(
        _handlePos,
        14,
        Paint()
          ..color = const Color(0xFF263238)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.drawCircle(
        _deleteCenter, 16, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(
      _deleteCenter,
      16,
      Paint()
        ..color = const Color(0xFFE53935)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final xPaint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 3;
    canvas.drawLine(_deleteCenter.translate(-7, -7),
        _deleteCenter.translate(7, 7), xPaint);
    canvas.drawLine(_deleteCenter.translate(-7, 7),
        _deleteCenter.translate(7, -7), xPaint);
  }
}

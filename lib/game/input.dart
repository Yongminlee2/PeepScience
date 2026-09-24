import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/widgets.dart'
    show Canvas, Color, Offset, Paint, PaintingStyle, Radius, Rect, RRect;

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
/// (e.g. `DragStartEvent.canvasPosition`, or a canvas position a caller has
/// otherwise reconstructed - see hud.dart's and this file's own
/// onDragUpdate doc comments for why a raw
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
  PiyakGame game,
  PartType type,
  Vector2 worldPos,
  double angleDeg, {
  int? excludeIndex,
}) {
  return rules.canPlaceAt(
    _existingBoxes(game, excludeIndex: excludeIndex),
    type,
    worldPos.x,
    worldPos.y,
    angleDeg,
    ballZone: game.stage.ballZone,
  );
}

/// If [type] is gear-family and a same-family preset/placement neighbor
/// exists within catch range of [rawWorldPos], returns the snapped landing
/// point; otherwise returns [rawWorldPos] unchanged. See
/// sim/placement_rules.dart's `snapGearPosition` for the actual math.
///
/// [excludeIndex] mirrors [canPlaceAt]'s own param: pass the part's own
/// index while moving an ALREADY-placed gear ([handleEditMoveDragEnd]) so it
/// never treats its own (live, mid-drag) box as the neighbor to snap
/// against - a fresh tray drop (hud.dart) has no such self to exclude,
/// hence the default null.
Vector2 snapGearPosition(
  PiyakGame game,
  PartType type,
  Vector2 rawWorldPos, {
  int? excludeIndex,
}) {
  final (x, y) = rules.snapGearPosition(
    _existingBoxes(game, excludeIndex: excludeIndex),
    type,
    rawWorldPos.x,
    rawWorldPos.y,
  );
  return Vector2(x, y);
}

/// Resolves a raw drop point into the actual landing position (snap-adjusted
/// for gear-family types, see [snapGearPosition]) and whether that position
/// is a legal placement (see [canPlaceAt]). Used for both the live
/// drag-ghost preview and the real drop, so the ghost always shows exactly
/// what dropping right now would do.
({Vector2 pos, bool valid}) resolveDrop(
  PiyakGame game,
  PartType type,
  Vector2 rawWorldPos,
) {
  final pos = snapGearPosition(game, type, rawWorldPos);
  return (pos: pos, valid: canPlaceAt(game, type, pos, 0));
}

/// Every existing footprint (stage presets, then live placements in order)
/// as the pure [rules.PlacementBox] type - the one place this file bridges
/// PiyakGame's Flutter/Flame-flavored state into sim/placement_rules.dart's
/// plain-Dart inputs.
Iterable<rules.PlacementBox> _existingBoxes(
  PiyakGame game, {
  int? excludeIndex,
}) sync* {
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
// mixes in DragCallbacks (see piyak_game.dart) and, being the root
// component, is the LAST candidate flame's dispatcher checks for any given
// pointer (every descendant is matched first - see flame's
// Component.componentsAtLocation) - so this never steals events from
// hud.dart's per-slot tray drags. DragStartEvent.canvasPosition is computed
// once per event independent of which component ends up receiving it
// (flame's PositionEvent/DisplacementEvent), so reading it here is exactly
// as correct as hud.dart's own identical usage; DragUpdateEvent needs the
// canvasDelta-accumulation dance documented on handleEditDragUpdate below
// instead, for the same reason hud.dart's onDragUpdate now does too.
//
// handleEditTapUp no longer takes a real TapUpEvent - PiyakGame has no
// TapCallbacks at all (see its own "Real-finger tap synthesis" doc comment
// for why: on a real device ANY pointer movement, even a few px of finger
// drift, hands the gesture arena to the drag recognizer instead, so a real
// onTapUp never fires). It's called with a plain canvas position instead,
// synthesized from a short/fast drag's START point once that drag ends -
// which is also why it fires on drag END, never on drag START: claiming a
// rotate-handle/ring-band or a placement move-grab has to win the race
// against a same-pointer deselect, same as it always had to against
// onTapDown.
//
// UX overhaul (owner-approved manipulation rework) - drag-START priority
// ladder, walked in this exact order every time PiyakGame.onDragStart fires
// (piyak_game.dart), each stage only getting a turn if the one before it
// declined:
//   1. the SELECTED part's rotate handle/ring band (handleEditDragStart) -
//      the knob's own hit-circle OR the ring-BAND annulus around it, see
//      kHandleHitRadiusM/kRingBandHalfWidthM.
//   2. any placement's footprint, i.e. grabbing it to move it
//      (handleEditMoveDragStart) - also selects it, so a bare grab (no
//      separate tap-to-select first) works.
//   3. a tray slot (hud.dart's _TraySlot) - already resolved BEFORE this
//      component ever sees the pointer, per the componentsAtLocation
//      ordering above; listed here only to keep the ladder in one place.
//   4. nothing - falls through as a tap candidate (_dispatchTap).
// Steps 1 and 2 are geometrically almost disjoint by construction (the ring
// band sits OUTSIDE the footprint - selectionRingRadiusM already adds
// kSelectionRingPadding on top of the enclosing radius) but for an
// elongated part (plank) the band's inner edge can still dip slightly inside
// the part's own AABB near its flat ends - the ladder's ORDER, not the
// geometry alone, is what makes step 1 win there, matching "rotate before
// move" for a part that's already selected. Both steps also defer to the
// delete-X button first (see _onDeleteButton below) - without that, a
// selected fan's small ring (band range ~0.35-0.95m) permanently brackets
// its own delete-X (fixed 0.6m above center) at every rotation angle, which
// would make that button unreachable by tap.

/// Extra visual margin (meters) added to a placed part's own footprint to
/// get its selection ring radius.
const double kSelectionRingPadding = 0.18;

/// Minimum world-space offset (meters, straight up i.e. smaller y) from a
/// placement's center to its delete-X button center. Shared contract:
/// "삭제 X는 부품 위 0.6m" - unlike the rotate handle, this does NOT turn
/// with the part's own angle. A part tall enough to reach past this pushes
/// the button further out, see [deleteButtonWorldPos].
const double kDeleteButtonOffsetM = 0.6;

/// Gap (meters) kept between a part's own top edge and the delete-X button
/// when the part is too tall for [kDeleteButtonOffsetM] to clear it - a
/// stood-up plank is 1m tall, so a fixed 0.6m put the X *inside* the plank
/// and stole the drags meant to move it.
const double kDeleteButtonClearanceM = 0.34;

/// Hit-test radius (meters) for the delete-X button.
const double kDeleteHitRadiusM = 0.28;

/// Hit-test radius (meters) for the rotate-handle knob. Generous-rotation
/// improvement bumped this from the original 0.24 - the knob is no longer
/// the ONLY way to grab a rotate either, see [kRingBandHalfWidthM].
const double kHandleHitRadiusM = 0.36;

/// Half-width (meters) of the selection ring's grabbable BAND, centered on
/// [selectionRingRadiusM]: a drag starting anywhere in this annulus - any
/// angle around the ring, not just on the knob - also claims a rotate (see
/// [handleEditDragStart]). The knob stays as the sole visual affordance
/// (SelectionOverlay still draws only the one dot); this just makes the
/// whole ring behave as one big handle, generous enough that a player
/// doesn't have to aim for a small dot to start rotating.
const double kRingBandHalfWidthM = 0.3;

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
Vector2 deleteButtonWorldPos(Placement p) {
  // boxForPart already accounts for rotation (and the paddle gear's bar), so
  // the button clears the part at every angle without a second geometry rule.
  final halfHeight = rules.boxForPart(p.type, p.x, p.y, p.angleDeg).halfY;
  final offset = max(
    kDeleteButtonOffsetM,
    halfHeight + kDeleteButtonClearanceM,
  );
  return Vector2(p.x, max(p.y - offset, kDeleteHitRadiusM));
}

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

/// PiyakGame's synthesized-tap dispatch (piyak_game.dart's _dispatchTap)
/// falls through to here for anything that isn't a win-overlay button or
/// the run toggle - i.e. this is the in-field select/delete/deselect
/// handler. Takes the tap's canvas position directly (not a TapUpEvent -
/// there are no tap events in this game at all anymore, see piyak_game.dart)
/// and only ever runs once a gesture is CONFIRMED as a tap, at its END -
/// never at its START, deliberately: acting immediately on pointer-down
/// would select/deselect BEFORE a rotate-handle drag on the very same
/// pointer got a chance to claim itself in handleEditDragStart, wrongly
/// clearing the selection out from under it (confirmed empirically while
/// building this originally - the drag's own onDragStart always saw
/// selectedIndex already wiped to null by then). _dispatchTap preserves
/// this ordering: it only fires from onDragEnd, after handleEditDragStart
/// (called from onDragStart, earlier in the same gesture) has already had
/// its chance to claim the pointer for a rotate instead.
///
/// Priority order once a tap is confirmed: delete-X (only if something's
/// already selected) > tap-a-part (select/switch) > tap-empty-field (clear
/// selection) - matches the brief's "탭하여 다른 부품 선택 시 전환/해제".
void handleEditTapUp(PiyakGame game, Vector2 canvasPos) {
  if (game.mode != GameMode.edit) return;
  final worldPos = canvasToWorldPx(game, canvasPos) / kPpm;
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

/// True if [worldPos] is inside [game]'s currently-selected placement's
/// delete-X hit circle, if any (false if nothing is selected). Consulted
/// FIRST by both [handleEditDragStart] and [handleEditMoveDragStart] - see
/// this section's header comment ("UX overhaul") for why the delete-X
/// button has to win any same-point ambiguity against either of them.
bool _onDeleteButton(PiyakGame game, Vector2 worldPos) {
  final idx = game.selectedIndex;
  if (idx == null || idx >= game.placements.length) return false;
  final del = deleteButtonWorldPos(game.placements[idx]);
  return (worldPos - del).length <= kDeleteHitRadiusM;
}

/// PiyakGame.onDragStart delegates here FIRST, per the drag-start priority
/// ladder (this section's header comment). Only claims the drag (sets
/// [PiyakGame.rotatingIndex]) when a rotatable part is selected AND the drag
/// starts either on its handle knob ([kHandleHitRadiusM]) or anywhere on its
/// selection ring's grabbable band ([kRingBandHalfWidthM]) - and not on its
/// delete-X ([_onDeleteButton], checked first). Otherwise a no-op, so the
/// drag falls through to [handleEditMoveDragStart] next (world-space drags
/// other than these and the tray - which lives under camera.viewport and,
/// being a descendant, is always matched before PiyakGame itself ever sees
/// the event - end up there).
void handleEditDragStart(PiyakGame game, DragStartEvent event) {
  if (game.mode != GameMode.edit) return;
  final idx = game.selectedIndex;
  if (idx == null || idx >= game.placements.length) return;
  final p = game.placements[idx];
  if (!Catalog.of(p.type).rotatable) return;
  final worldPos = canvasToWorldPx(game, event.canvasPosition) / kPpm;
  if (_onDeleteButton(game, worldPos)) return;
  final onKnob =
      (worldPos - rotateHandleWorldPos(p)).length <= kHandleHitRadiusM;
  final distFromCenter = (worldPos - Vector2(p.x, p.y)).length;
  final onRingBand =
      (distFromCenter - selectionRingRadiusM(p.type)).abs() <=
      kRingBandHalfWidthM;
  if (!onKnob && !onRingBand) return;
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
/// hud.dart's onDragUpdate doc comment for the two ways flame's recognizer
/// can construct a DragUpdateDetails (accepted-before-any-movement vs.
/// accepted-by-the-first-movement) and why accumulating canvasDelta is
/// correct either way. PiyakGame no longer has any competing TapCallbacks
/// recognizer to trigger the second path (see this file's Task 8 header
/// comment and piyak_game.dart's own "Real-finger tap synthesis" comment),
/// but this accumulation is harmless - and still correct - regardless, so
/// it's left in place rather than reverted.
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
  final valid = canPlaceAt(
    game,
    p.type,
    Vector2(p.x, p.y),
    p.angleDeg,
    excludeIndex: idx,
  );
  if (!valid) {
    game.setPlacementAngle(idx, game.rotateFallbackAngleDeg);
  }
}

/// PiyakGame.onDragStart delegates here SECOND, after [handleEditDragStart]
/// has had its chance to claim a rotate (ladder step 2 - see this section's
/// header comment) - the caller only invokes this when that call left
/// [PiyakGame.rotatingIndex] untouched. Claims the drag (sets
/// [PiyakGame.movingIndex] + [PiyakGame.movingPointerId]) when it starts
/// inside any placement's footprint ([_placementIndexAt]) and isn't on the
/// selected part's delete-X ([_onDeleteButton], same reason
/// [handleEditDragStart] checks it first) - AND no other pointer already
/// owns a move (`movingIndex != null` guard, checked first): without it, a
/// second finger touching a different placement's footprint while the first
/// is still mid-drag would silently overwrite movingIndex/moveGrabOffsetM/
/// movePreDragPosM/selectedIndex out from under the first finger, which
/// then live-commits its OWN pointer's future updates onto the wrong
/// bookkeeping and, on release, never gets its own revert-if-illegal check
/// (handleEditMoveDragEnd runs against whatever `movingIndex` points at NOW,
/// not the part this pointer actually grabbed). A declined second pointer
/// simply falls through the ladder as an ordinary tap candidate instead -
/// still fully usable for e.g. tapping a different, unclaimed part.
///
/// Also selects the grabbed placement immediately (owner's playtested "grab
/// it, no separate select tap needed" - Improvement B) and records the grab
/// offset so [handleEditMoveDragUpdate] keeps the part under the same
/// finger point it was grabbed at, instead of snapping its center to the
/// pointer.
void handleEditMoveDragStart(PiyakGame game, DragStartEvent event) {
  if (game.mode != GameMode.edit) return;
  if (game.movingIndex != null) return;
  if (game.rotatingIndex != null) return;
  final worldPos = canvasToWorldPx(game, event.canvasPosition) / kPpm;
  if (_onDeleteButton(game, worldPos)) return;
  final idx = _placementIndexAt(game, worldPos);
  if (idx == null) return;
  final p = game.placements[idx];
  game.selectedIndex = idx;
  game.movingIndex = idx;
  game.movingPointerId = event.pointerId;
  game.moveGrabOffsetM = worldPos - Vector2(p.x, p.y);
  game.movePreDragPosM = Vector2(p.x, p.y);
  game.moveDragCanvasPos = event.canvasPosition;
}

/// PiyakGame.onDragUpdate delegates here. Live-commits the dragged center on
/// every tick via [PiyakGame.setPlacementPosition] - same "clamp on
/// release" choice [handleEditDragUpdate] makes for rotation, and for the
/// same reason: the player needs to see the part actually follow their
/// finger, even over a spot that would be rejected on release (canPlaceAt is
/// only consulted for the live ring tint, [SelectionOverlay], and the
/// revert check in [handleEditMoveDragEnd]). No gear-snap while dragging
/// live (unlike the tray ghost's [resolveDrop]) - only the raw grabbed
/// position; snapping only ever applies at the moment of commit, see
/// [handleEditMoveDragEnd].
///
/// Cost note: unlike rotation's angle (gated behind a 5-degree snap, so
/// setPlacementAngle/_rebuildViews only fire roughly a dozen times across a
/// full sweep), position has no such natural quantization here, so this
/// calls [PiyakGame.setPlacementPosition] - and therefore
/// PiyakGame._rebuildViews(), a full remove+recreate of every PartView - on
/// EVERY drag-update frame. Rebuilding a handful of PartViews (this game's
/// scenes top out around a dozen parts) on every touch-move frame is cheap
/// enough to be unmeasurable in practice; a scene with hundreds of parts
/// would instead want to move the grabbed PartView's own position directly
/// and only touch `placements`/_rebuildViews() once, on release.
///
/// Tracks the pointer via [PiyakGame.moveDragCanvasPos] + event.canvasDelta,
/// not event.canvasStartPosition/canvasEndPosition - identical reasoning to
/// [handleEditDragUpdate]'s own doc comment.
///
/// Guarded by [PiyakGame.movingPointerId] (in addition to the usual
/// [PiyakGame.movingIndex] null-check): PiyakGame.onDragUpdate calls this
/// for EVERY pointer's update, not just the one that actually grabbed the
/// part (there is no per-component dispatch here, see this file's "UX
/// overhaul" header comment) - without this check, a second pointer's own
/// finger-wobble would get added onto the FIRST pointer's
/// moveDragCanvasPos/moveGrabOffsetM math, yanking the grabbed part around
/// in response to a completely unrelated touch.
void handleEditMoveDragUpdate(PiyakGame game, DragUpdateEvent event) {
  final idx = game.movingIndex;
  final lastCanvasPos = game.moveDragCanvasPos;
  if (idx == null ||
      idx >= game.placements.length ||
      lastCanvasPos == null ||
      event.pointerId != game.movingPointerId) {
    return;
  }
  final canvasPos = lastCanvasPos + event.canvasDelta;
  game.moveDragCanvasPos = canvasPos;
  final worldPos = canvasToWorldPx(game, canvasPos) / kPpm;
  final center = worldPos - game.moveGrabOffsetM;
  game.setPlacementPosition(idx, center.x, center.y);
}

/// PiyakGame.onDragEnd delegates here (a cancelled drag arrives here too,
/// via DragCallbacks' default onDragCancel -> onDragEnd forwarding, same as
/// [handleEditDragEnd]) with [traveled] = this same pointer's total path
/// length in canvas px (PiyakGame.onDragEnd's own tap-candidate bookkeeping
/// - the same number that decides whether _dispatchTap treats the gesture
/// as a tap).
///
/// Guarded by [PiyakGame.movingPointerId] first - see
/// [handleEditMoveDragUpdate]'s doc comment for why PiyakGame routes every
/// pointer's end event here, not just the owning one; a non-owning pointer's
/// end must leave the still-in-flight move's state completely untouched.
///
/// Two outcomes for the OWNING pointer:
/// - [traveled] never left tap territory (< [PiyakGame.kTapMaxTravelPx],
///   same threshold _dispatchTap uses): NOT a move, no matter how long the
///   finger sat there - reverts to [PiyakGame.movePreDragPosM] verbatim, no
///   gear-snap, no canPlaceAt re-check. Without this, a plain tap-to-select
///   on a gear that's already meshed with 3+ neighbors would run
///   [snapGearPosition] on release like any other move and could silently
///   re-snap it to a DIFFERENT nearest neighbor, changing which gears mesh
///   with which - a connectivity change nobody asked for from what looked
///   like a tap.
/// - otherwise: a real move - snaps gear-family parts the same way a tray
///   drop does ([snapGearPosition], with the part itself excluded so it
///   never snaps against its own live box), then reverts to
///   [PiyakGame.movePreDragPosM] if the landing spot is still illegal after
///   that snap.
///
/// Either way, [PiyakGame.setPlacementPosition] (and the full
/// remove+recreate `_rebuildViews()` it triggers) only runs if the target
/// actually differs from the live position - a no-move tap or a legal
/// no-snap landing both typically already ARE the target, so this skips a
/// pointless extra rebuild on the most common releases. The part stays
/// selected either way - only its position is ever in question here.
void handleEditMoveDragEnd(
  PiyakGame game,
  DragEndEvent event, {
  required double traveled,
}) {
  final idx = game.movingIndex;
  if (idx == null || event.pointerId != game.movingPointerId) return;
  game.movingIndex = null;
  game.movingPointerId = null;
  game.moveDragCanvasPos = null;
  if (idx >= game.placements.length) return;
  final p = game.placements[idx];
  Vector2 target;
  if (traveled < PiyakGame.kTapMaxTravelPx) {
    target = game.movePreDragPosM;
  } else {
    final landing = snapGearPosition(
      game,
      p.type,
      Vector2(p.x, p.y),
      excludeIndex: idx,
    );
    final valid = canPlaceAt(
      game,
      p.type,
      landing,
      p.angleDeg,
      excludeIndex: idx,
    );
    target = valid ? landing : game.movePreDragPosM;
  }
  if (p.x != target.x || p.y != target.y) {
    game.setPlacementPosition(idx, target.x, target.y);
  }
}

// 선택 고리 색 - 개발용 파란색 대신 캔디 팔레트의 따뜻한 노랑(손맛 패스,
// hud.dart의 _kCountChip/_kOutline과 같은 계열). 이 파일은 hud.dart의
// private 상수를 가져올 수 없어 그대로 다시 적는다(SelectionOverlay.render의
// 초콜릿 손잡이 외곽선과 같은 이유 - 아래 그 리터럴 참고).
const Color _kRingValidColor = Color(0xFFF4C542);

/// [radius]의 원을 실선 대신 점선(대시)으로 그린다 - 반지름/히트 영역은
/// 전혀 건드리지 않고 이 함수를 부르는 쪽의 순수 시각 표현만 바뀐다.
/// [dashPx]/[gapPx]는 원의 둘레를 따라 호(arc) 길이 기준.
void _drawDashedCircle(
  Canvas canvas,
  Offset center,
  double radius,
  Paint paint, {
  double dashPx = 12,
  double gapPx = 8,
}) {
  final dashAngle = dashPx / radius;
  final gapAngle = gapPx / radius;
  final rect = Rect.fromCircle(center: center, radius: radius);
  var angle = 0.0;
  while (angle < 2 * pi) {
    final sweep = min(dashAngle, 2 * pi - angle);
    canvas.drawArc(rect, angle, sweep, false, paint);
    angle += dashAngle + gapAngle;
  }
}

/// Edit-mode-only visual for [PiyakGame.selectedIndex]: a ring around the
/// selected placement, a delete-X 0.6m above it, and (only when the type is
/// rotatable - plank, fan) a rotate-handle knob on the ring's edge, tinted
/// red while a rotate OR a move drag ([PiyakGame.movingIndex]) is sitting at
/// an invalid angle/position. Purely a renderer - all
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
  late double _bodyRadiusPx;
  late double _barWidthPx;
  late double _barHeightPx;
  late double _partAngleRad;
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
    final spec = Catalog.of(p.type);
    // Trace exactly the shapes placement_rules.dart judges: a round body, a
    // rectangular body, or - for the paddle gear alone - both, drawn as the
    // union they are judged as. 0 means "this part has no such body".
    _bodyRadiusPx = (spec.radius ?? 0) * kPpm;
    _barWidthPx = (spec.w ?? 0) * kPpm;
    _barHeightPx = (spec.h ?? 0) * kPpm;
    _partAngleRad = p.angleDeg * pi / 180;
    _showHandle = Catalog.of(p.type).rotatable;
    if (_showHandle) {
      final h = rotateHandleWorldPos(p);
      _handlePos = _px(h.x, h.y);
    }
    final del = deleteButtonWorldPos(p);
    _deleteCenter = _px(del.x, del.y);
    _invalid =
        (game.rotatingIndex == idx || game.movingIndex == idx) &&
        !canPlaceAt(
          game,
          p.type,
          Vector2(p.x, p.y),
          p.angleDeg,
          excludeIndex: idx,
        );
  }

  static Offset _px(double xM, double yM) => Offset(xM * kPpm, yM * kPpm);

  @override
  void render(Canvas canvas) {
    if (!_visible) return;
    final ringColor = _invalid ? const Color(0xFFE53935) : _kRingValidColor;
    final outlinePaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    if (_bodyRadiusPx > 0) {
      _drawDashedCircle(canvas, _center, _bodyRadiusPx + 12, outlinePaint);
    }
    if (_barWidthPx > 0) {
      // A long plank inside its old enclosing circle looked like a debug
      // gizmo: the circle had to be as tall as the entire plank was wide.
      // Show the selected physical footprint instead, while keeping the
      // generous invisible ring-band hit target and handle geometry intact.
      canvas.save();
      canvas.translate(_center.dx, _center.dy);
      canvas.rotate(_partAngleRad);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: _barWidthPx + 24,
        height: _barHeightPx + 24,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        Paint()..color = ringColor.withAlpha(34),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        outlinePaint,
      );
      canvas.restore();
    }
    if (_showHandle) {
      canvas.drawLine(
        _center,
        _handlePos,
        Paint()
          ..color = ringColor
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        _handlePos,
        14,
        Paint()..color = const Color(0xFFFFC107),
      );
      canvas.drawCircle(
        _handlePos,
        14,
        Paint()
          // 초콜릿 톤 손잡이 외곽선 - hud.dart 스킨 패스와 팔레트를 맞춘다
          // (같은 값이지만 이 파일은 hud.dart의 private 상수를 가져올 수
          // 없어 그대로 다시 적음).
          ..color = const Color(0xFF4E342E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.drawCircle(
      _deleteCenter,
      16,
      Paint()..color = const Color(0xFFFFFFFF),
    );
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
    canvas.drawLine(
      _deleteCenter.translate(-7, -7),
      _deleteCenter.translate(7, 7),
      xPaint,
    );
    canvas.drawLine(
      _deleteCenter.translate(-7, 7),
      _deleteCenter.translate(7, -7),
      xPaint,
    );
  }
}

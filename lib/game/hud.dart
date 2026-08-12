import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/widgets.dart'
    show
        Canvas,
        Color,
        FontWeight,
        Offset,
        Paint,
        Radius,
        Rect,
        RRect,
        TextStyle;

import '../sim/catalog.dart';
import '../sim/stage_data.dart';
import 'input.dart';
import 'part_view.dart';
import 'piyak_game.dart';

const Color _kBarBg = Color(0xFFECEFF1);
const Color _kSlotBg = Color(0xFFFFFFFF);
const Color _kSlotEmptyBg = Color(0x55FFFFFF);
const Color _kGhostValidColor = Color(0x8843A047);
const Color _kGhostInvalidColor = Color(0x88E53935);

/// Screen-space HUD strip along the bottom of the 1600x900 logical screen,
/// one slot per `stage.tray` entry showing its remaining count. Mounted via
/// `game.camera.viewport.add(TrayBar(game))` - NOT `world`/`viewfinder` - so
/// it always sits at the bottom of the visible canvas regardless of
/// letterboxing or any future camera pan/zoom (see camera_component.dart's
/// own doc comment: viewport children are unaffected by the viewfinder).
class TrayBar extends PositionComponent {
  // 1600x900 matches PiyakGame's fixed-resolution camera (16x9m * kPpm) -
  // see piyak_game.dart's CameraComponent.withFixedResolution call.
  TrayBar(this.game)
      : super(
          position: Vector2(0, 900 - barHeight),
          size: Vector2(1600, barHeight),
        );

  static const double barHeight = 150;
  static const double slotSize = 120;
  static const double slotGap = 20;
  static const double slotMarginTop = (barHeight - slotSize) / 2;

  final PiyakGame game;

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < game.stage.tray.length; i++) {
      add(_TraySlot(game, game.stage.tray[i], i));
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), Paint()..color = _kBarBg);
  }
}

/// One tray slot: shows the remaining count for a [TrayEntry] and drives the
/// drag-to-place gesture. Remaining count is derived - `entry.count` minus
/// how many of that type are already in `game.placements` - never stored
/// separately, so a slot frees back up automatically whenever a placement of
/// its type is removed (Task 8's delete needs no extra bookkeeping here).
class _TraySlot extends PositionComponent with DragCallbacks {
  _TraySlot(this.game, this.entry, int index)
      : super(
          position: Vector2(
            TrayBar.slotGap + index * (TrayBar.slotSize + TrayBar.slotGap),
            TrayBar.slotMarginTop,
          ),
          size: Vector2.all(TrayBar.slotSize),
        );

  final PiyakGame game;
  final TrayEntry entry;

  late final TextComponent _countLabel = TextComponent(
    text: '$_remaining',
    position: Vector2(size.x / 2, size.y - 6),
    anchor: Anchor.bottomCenter,
    textRenderer: TextPaint(
      style: const TextStyle(
        color: Color(0xFF263238),
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  // Drag-in-progress state; all null/absent when no drag from this slot is
  // active (either never started, or already ended/cleaned up).
  PartView? _ghost;
  bool? _ghostValid;
  ({Vector2 pos, bool valid})? _lastResult;
  // Running canvas-space pointer position for the drag in progress - see
  // onDragUpdate's doc comment for why this is tracked incrementally
  // instead of read straight off each event.
  Vector2? _lastCanvasPos;

  int get _remaining =>
      entry.count - game.placements.where((p) => p.type == entry.type).length;

  @override
  Future<void> onLoad() async {
    add(_countLabel);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _countLabel.text = '$_remaining';
  }

  @override
  void render(Canvas canvas) {
    final empty = _remaining <= 0;
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = empty ? _kSlotEmptyBg : _kSlotBg,
    );
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2 - 10),
      26,
      Paint()..color = Color(Catalog.of(entry.type).color),
    );
  }

  // Run mode ignores tray drags entirely: this guard (plus the remaining<=0
  // guard) is the only gate - both leave _ghost null, so onDragUpdate/onEnd
  // below become no-ops for the rest of this gesture.
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (game.mode != GameMode.edit || _remaining <= 0) return;
    _lastCanvasPos = event.canvasPosition;
    _track(event.canvasPosition);
  }

  // Accumulates event.canvasDelta onto our own running _lastCanvasPos,
  // rather than reading canvasStartPosition/canvasEndPosition straight off
  // the event - neither is reliably "the true current pointer position" by
  // itself. flame's MultiDragScaleGestureRecognizer builds
  // DragUpdateDetails two different ways depending on exactly when in the
  // gesture-arena competition this drag got accepted:
  //  - accepted BEFORE any movement (true when this recognizer is the ONLY
  //    one competing for the pointer): globalPosition is already the true
  //    current position on every update, so canvasStartPosition
  //    (= deviceStartPosition = raw globalPosition, no +delta) is correct
  //    and canvasEndPosition (= globalPosition+delta) double-counts and
  //    overshoots. This was the whole story when this comment was first
  //    written (Task 7) - but Task 8 gave PiyakGame its own TapCallbacks,
  //    which is now ALSO in the arena for every pointer in the game (tap
  //    and drag recognizers are registered game-wide, not per-component -
  //    see input.dart's Task 8 section header comment), which enables the
  //    second case below for tray drags too.
  //  - accepted BY the first movement itself (true whenever something
  //    else - e.g. that TapCallbacks - is also competing): the FIRST
  //    onDragUpdate instead carries globalPosition = the gesture's
  //    original down-point with delta = the FULL move accumulated before
  //    acceptance, so canvasStartPosition is stale (still the down-point)
  //    while canvasEndPosition (= start+delta) is the one that's actually
  //    correct for THAT event - then flips back to overshooting for every
  //    later update in the same gesture, per the first bullet.
  // event.canvasDelta (= canvasEndPosition - canvasStartPosition) is
  // reliably correct either way - it always represents "how far did the
  // pointer move to produce this specific event" - so accumulating it onto
  // a position seeded from the unambiguous DragStartEvent.canvasPosition
  // sidesteps the whole ambiguity.
  @override
  void onDragUpdate(DragUpdateEvent event) {
    final last = _lastCanvasPos;
    if (_ghost == null || last == null) return;
    _lastCanvasPos = last + event.canvasDelta;
    _track(_lastCanvasPos!);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final ghost = _ghost;
    final result = _lastResult;
    _ghost = null;
    _ghostValid = null;
    _lastResult = null;
    _lastCanvasPos = null;
    ghost?.removeFromParent();
    if (result != null && result.valid) {
      game.addPlacement(
        Placement(type: entry.type, x: result.pos.x, y: result.pos.y, angleDeg: 0),
      );
    }
  }

  // Tracks the pointer: resolves the current world position to a candidate
  // (snap-adjusted for gear-family types) + validity via input.dart's
  // resolveDrop, then keeps the ghost PartView at that exact position so it
  // always previews precisely what dropping right now would do. The ghost
  // is only rebuilt when its valid/invalid tint needs to flip (PartView's
  // paints are `late final`, baked in at construction) - a plain position
  // update is enough on every other frame.
  void _track(Vector2 canvasPos) {
    final worldM = canvasToWorldPx(game, canvasPos) / kPpm;
    final result = resolveDrop(game, entry.type, worldM);
    _lastResult = result;
    if (_ghost == null || _ghostValid != result.valid) {
      _ghost?.removeFromParent();
      final tint = result.valid ? _kGhostValidColor : _kGhostInvalidColor;
      final g = PartView(
        part: entry.type,
        posM: result.pos,
        angleRad: 0,
        ghostColor: tint,
      );
      _ghost = g;
      _ghostValid = result.valid;
      game.world.add(g);
    } else {
      _ghost!.position = result.pos * kPpm;
    }
  }
}

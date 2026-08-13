import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/particles.dart';
import 'package:flutter/widgets.dart'
    show
        BlurStyle,
        Canvas,
        Color,
        FontWeight,
        MaskFilter,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        Radius,
        Rect,
        RRect,
        TextStyle,
        VoidCallback;

import '../services/sound.dart';
import '../sim/catalog.dart';
import '../sim/stage_data.dart';
import '../ui/strings.dart';
import 'input.dart';
import 'part_view.dart';
import 'piyak_game.dart';

// 스티커 스킨 팔레트 - docs/이미지-발주서.md의 외곽선(#4E342E, 18~24px@256px/m -
// HUD 스케일에선 ~4~6px)·채도(0.35~0.55) 기준을 HUD 크롬에도 적용해
// part_view.dart의 "사탕 채움 + 초콜릿 외곽선" 재질언어와 통일한다(오너
// 피드백: 트레이/버튼/목표 배지가 손 안 댄 개발용 UI - "정체불명 박스" -
// 로 읽힘). 색은 전부 여기 한 곳에 모아 둔다 - 흩어진 리터럴을 지적한 T9
// 리뷰를 반복하지 않기 위함.
const Color _kOutline = Color(0xFF4E342E); // 초콜릿 외곽선 - 모든 스티커 카드 공용
const double _kOutlineWidth = 5;
const Color _kBarBg = Color(0xFFFFF3DC); // 트레이 바 패널(진한 크림)
const Color _kCardBg = Color(0xFFFFFBF0); // 슬롯/배지/오버레이 버튼 카드(밝은 크림)
const Color _kSlotEmptyBg = Color(0x99FFFBF0);
const Color _kCountChip = Color(0xFFFFCA28); // 트레이 개수 칩(캔디 골드)
const Color _kShadow = Color(0x33000000); // 카드 소프트 그림자
const double _kBarBorderWidth = 6;

const Color _kCandyGreenFill = Color(0xFF66BB6A);
const Color _kCandyGreenBand = Color(0xFF43A047); // ▶ 바닥 밴드 + 다음 아이콘
const Color _kCandyCoralFill = Color(0xFFFF7043);
const Color _kCandyCoralBand = Color(0xFFE64A19); // ■ 바닥 밴드 + 다시 아이콘 + 깃발

const Color _kGhostValidColor = Color(0x8843A047);
const Color _kGhostInvalidColor = Color(0x88E53935);

/// 공용 스티커 카드 크롬: 소프트 그림자 + 크림 채움 + 초콜릿 외곽선. 트레이
/// 슬롯/목표 배지/승리 오버레이 버튼이 전부 이 한 함수를 공유해 HUD 전체가
/// 하나의 재질로 읽힌다(part_view.dart가 부품마다 같은 채움+외곽선 짝을
/// 반복하는 것과 같은 이유).
void _drawStickerCard(Canvas canvas, Rect rect, double radius, Color fill) {
  final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  canvas.drawRRect(
    rr.shift(const Offset(0, 3)),
    Paint()
      ..color = _kShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawRRect(rr, Paint()..color = fill);
  canvas.drawRRect(
    rr,
    Paint()
      ..color = _kOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kOutlineWidth,
  );
}

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
    // 초콜릿 상단 테두리 - 놀이판과 트레이 사이 경계를 사탕/스티커 재질로.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, _kBarBorderWidth),
      Paint()..color = _kOutline,
    );
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
        color: _kOutline,
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
    _drawStickerCard(canvas, rect, 14, empty ? _kSlotEmptyBg : _kCardBg);
    final partCenter = Offset(size.x / 2, size.y / 2 - 10);
    canvas.drawCircle(
      partCenter,
      26,
      Paint()..color = Color(Catalog.of(entry.type).color),
    );
    canvas.drawCircle(
      partCenter,
      26,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // 개수 칩 - 작은 캔디 원 위에 개수를 얹어(_countLabel, child라 이 뒤에
    // 그려짐) "정체불명 박스"가 아니라 라벨 있는 카드로 읽히게 한다.
    final chipCenter = Offset(size.x / 2, size.y - 20);
    canvas.drawCircle(chipCenter, 17, Paint()..color = _kCountChip);
    canvas.drawCircle(
      chipCenter,
      17,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
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
  //    written (Task 7) - Task 8 then gave PiyakGame its own TapCallbacks,
  //    which was ALSO in the arena for every pointer in the game for a
  //    while (tap and drag recognizers are registered game-wide, not
  //    per-component), enabling the second case below for tray drags too;
  //    the real-touch fix later removed TapCallbacks from this game
  //    entirely (see piyak_game.dart's "Real-finger tap synthesis" comment)
  //    but this accumulation is harmless either way, so it's left as-is.
  //  - accepted BY the first movement itself (true whenever something
  //    else - e.g. a competing tap recognizer - is also competing): the FIRST
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
    if (game.mode != GameMode.edit) {
      // A second finger started a run (RunToggleButton) while this drag was
      // still in flight - drop the ghost instead of letting it keep
      // tracking into a mode _rebuildViews() no longer expects it in.
      _cancelDrag();
      return;
    }
    _lastCanvasPos = last + event.canvasDelta;
    _track(_lastCanvasPos!);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (game.mode != GameMode.edit) {
      // Same mid-drag mode flip as onDragUpdate above, just caught at
      // release instead of an intermediate move - either way, committing a
      // placement now (mode == run) would desync placements.length from
      // the SimWorld bodies already built for this run and trip
      // _rebuildViews()'s own bodies/entries-count assert.
      _cancelDrag();
      return;
    }
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
      // Auto-select on drop (owner-approved UX overhaul, Improvement A) -
      // addPlacement() only ever appends, so the new entry is always the
      // last index. One less tap, and immediately shows the rotate handle
      // for rotatable types.
      game.selectedIndex = game.placements.length - 1;
      Sound.play(Sfx.place);
    }
  }

  // Shared by the mode-flip-mid-drag branches above: drops the ghost
  // component and clears every piece of in-flight-drag state, without
  // committing a placement.
  void _cancelDrag() {
    _ghost?.removeFromParent();
    _ghost = null;
    _ghostValid = null;
    _lastResult = null;
    _lastCanvasPos = null;
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

// -----------------------------------------------------------------------
// Task 9: run control + win celebration.

/// Bottom-right ▶/■ toggle for [PiyakGame.mode] - screen-space HUD like
/// [TrayBar] (same camera.viewport reasoning, see that class's doc
/// comment), positioned just above the tray strip so it never competes for
/// space with a stage's tray slots regardless of how many the stage has.
/// Edit mode shows a play triangle and starts the run; run mode shows a
/// stop square and returns to edit - except while [WinOverlay] is up
/// (`game.sim!.cleared`), when [activate] is a no-op: the overlay's own
/// buttons (다시/다음) are the only way out of a cleared run, and a stray
/// tap on this now-covered button must not silently reset out from under
/// it (see [WinOverlay]'s doc comment for the matching half of this).
///
/// No TapCallbacks - [PiyakGame]'s tap-synthesis dispatch calls [activate]
/// directly once it resolves a short drag as a tap on this button's screen
/// rect (via componentsAtPoint - see piyak_game.dart's "Real-finger tap
/// synthesis" comment for why a real onTapUp is unreachable on this button
/// on a real device).
class RunToggleButton extends PositionComponent {
  RunToggleButton(this.game)
      : super(
          position: Vector2(
            1600 - margin - buttonDiameter,
            900 - TrayBar.barHeight - margin - buttonDiameter,
          ),
          size: Vector2.all(buttonDiameter),
        );

  static const double buttonDiameter = 120;
  static const double margin = 20;
  static const double _bandHeight = 10;

  final PiyakGame game;

  /// Starts a run (edit mode) or returns to edit (run mode, unless
  /// [WinOverlay] is up - see this class's own doc comment). The single
  /// entry point for "this button was activated", called from
  /// [PiyakGame]'s synthesized-tap dispatch.
  void activate() {
    if (game.mode == GameMode.edit) {
      game.startRun();
    } else if (game.sim?.cleared != true) {
      game.resetToEdit();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final r = size.x / 2;
    final playing = game.mode == GameMode.edit;
    final fill = playing ? _kCandyGreenFill : _kCandyCoralFill;
    final band = playing ? _kCandyGreenBand : _kCandyCoralBand;
    // 눌린 장난감 버튼처럼 바닥에 어두운 밴드가 살짝 남도록: 어두운 원판을
    // 먼저 채우고, 원 안으로 클립한 밝은 사각형으로 바닥 _bandHeight만 남기고
    // 덮는다.
    canvas.drawCircle(c, r, Paint()..color = band);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawRect(
      Rect.fromLTWH(c.dx - r, c.dy - r, r * 2, r * 2 - _bandHeight),
      Paint()..color = fill,
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      r - _kOutlineWidth / 2,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kOutlineWidth,
    );
    if (playing) {
      _drawPlayIcon(canvas, c, r * 0.5);
    } else {
      _drawStopIcon(canvas, c, r * 0.5);
    }
  }

  void _drawPlayIcon(Canvas canvas, Offset c, double r) {
    final path = Path()
      ..moveTo(c.dx - r * 0.6, c.dy - r)
      ..lineTo(c.dx - r * 0.6, c.dy + r)
      ..lineTo(c.dx + r, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = _kCardBg);
  }

  void _drawStopIcon(Canvas canvas, Offset c, double r) {
    final rect = Rect.fromCenter(center: c, width: r * 1.3, height: r * 1.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = _kCardBg,
    );
  }
}

/// Top-left "미션 카드" (goal-type icon + a tiny flag accent) - deliberately
/// no text (shared-contract: icon only), so it reads at a glance regardless
/// of locale. Screen-space HUD like [TrayBar]/[RunToggleButton]. `stage.goal`
/// never changes over a PiyakGame's lifetime, so unlike [WinOverlay] this is
/// added once in [PiyakGame.onLoad] and never removed/rebuilt. Icon shapes
/// echo part_view.dart's own painters for the same preset (basket/button) or
/// part (balloon), shrunk to badge size; toppleDominoes has no single-part
/// echo in part_view (domino renders as a plain box there), so its icon is
/// a small two-tile motif (one upright, one tilted) instead.
///
/// Also tappable ([activate]) - replays the goal-object pulse
/// ([PiyakGame.triggerGoalPulse]) on demand, same synthesized-tap mechanism
/// as [RunToggleButton.activate]/[WinOverlayButton.onTap] (see
/// piyak_game.dart's "Real-finger tap synthesis" comment).
class GoalBadge extends PositionComponent {
  GoalBadge(this.game)
      : super(position: Vector2.all(margin), size: Vector2.all(cardSize));

  static const double margin = 20;
  static const double cardSize = 96;

  final PiyakGame game;

  /// The single entry point for "this badge was tapped" - called from
  /// [PiyakGame]'s synthesized-tap dispatch. Mirrors
  /// [RunToggleButton.activate]'s own role.
  void activate() => game.triggerGoalPulse();

  @override
  void render(Canvas canvas) {
    _drawStickerCard(canvas, Rect.fromLTWH(0, 0, size.x, size.y), 18, _kCardBg);
    final c = Offset(size.x / 2, size.y / 2);
    switch (game.stage.goal.type) {
      case GoalType.ballInBasket:
        _drawBasket(canvas, c);
      case GoalType.pressButton:
        _drawButton(canvas, c);
      case GoalType.popBalloons:
        _drawBalloon(canvas, c);
      case GoalType.toppleDominoes:
        _drawDominoes(canvas, c);
    }
    _drawFlagAccent(canvas);
  }

  // "이게 목표"라는 뜻을 글자 없이 더하는 작은 깃발 - 오너 피드백("정체불명
  // 박스")에 대한 최소 추가. 카드 오른쪽 위 구석, 다른 아이콘들과 겹치지
  // 않는 자리.
  void _drawFlagAccent(Canvas canvas) {
    final poleTop = Offset(size.x - 24, 10);
    final poleBottom = Offset(size.x - 24, 32);
    canvas.drawLine(
      poleTop,
      poleBottom,
      Paint()
        ..color = _kOutline
        ..strokeWidth = 3,
    );
    final flag = Path()
      ..moveTo(poleTop.dx, poleTop.dy)
      ..lineTo(poleTop.dx + 16, poleTop.dy + 6)
      ..lineTo(poleTop.dx, poleTop.dy + 12)
      ..close();
    canvas.drawPath(flag, Paint()..color = _kCandyCoralFill);
  }

  // Mini basket: same floor+two-walls "U" envelope as PartView._renderBasket.
  void _drawBasket(Canvas canvas, Offset c) {
    final paint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawRect(
        Rect.fromCenter(center: c.translate(0, 14), width: 46, height: 10),
        paint);
    canvas.drawRect(
        Rect.fromCenter(center: c.translate(-20, 0), width: 8, height: 30),
        paint);
    canvas.drawRect(
        Rect.fromCenter(center: c.translate(20, 0), width: 8, height: 30),
        paint);
  }

  // Mini button: same half-round dome as PartView._renderButton.
  void _drawButton(Canvas canvas, Offset c) {
    final rect = Rect.fromCircle(center: c.translate(0, 8), radius: 26);
    canvas.drawArc(
        rect, pi, pi, true, Paint()..color = const Color(0xFFEF9A9A));
  }

  // Mini balloon: same oval+string as PartView._renderBalloon.
  void _drawBalloon(Canvas canvas, Offset c) {
    final paint = Paint()..color = const Color(0xFFF48FB1);
    final top = c.translate(0, -6);
    canvas.drawOval(
        Rect.fromCenter(center: top, width: 34, height: 42), paint);
    canvas.drawLine(
      top.translate(0, 21),
      top.translate(0, 34),
      Paint()
        ..color = const Color(0xFF263238)
        ..strokeWidth = 2,
    );
  }

  // Mini dominoes: one upright + one mid-topple tile.
  void _drawDominoes(Canvas canvas, Offset c) {
    final paint = Paint()..color = const Color(0xFFFFCC80);
    canvas.drawRect(
        Rect.fromCenter(center: c.translate(-10, 6), width: 14, height: 40),
        paint);
    canvas.save();
    canvas.translate(c.dx + 16, c.dy + 16);
    canvas.rotate(0.9);
    canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 14, height: 40), paint);
    canvas.restore();
  }
}

/// Shown once per run, the frame `sim.cleared` first becomes true (see
/// [PiyakGame]'s accumulator loop in `update`) - dimmed backdrop + confetti
/// + a literal 'CLEAR!' headline + 다시(retry)/다음(next) buttons. Mounted
/// under camera.viewport (screen-space, same reasoning as [TrayBar]) with a
/// priority above every other viewport child (TrayBar/RunToggleButton/
/// GoalBadge all default to 0) so it always draws on top - mirrors
/// input.dart's SelectionOverlay using a high priority for the same reason
/// in the world tree.
///
/// Removed by `PiyakGame._removeWinOverlay()` - the single choke point both
/// `startRun()` and `resetToEdit()` already call regardless of who
/// triggered them, so it (and every child added below: confetti/text/
/// buttons, all removed with it per Flame's own cascading
/// `Component._remove`) can never linger into edit mode or a fresh run.
class WinOverlay extends PositionComponent {
  WinOverlay(this.game)
      : super(
          position: Vector2.zero(),
          size: Vector2(1600, 900),
          priority: 100,
        );

  final PiyakGame game;

  static const double buttonSize = 140;
  static const Offset retryButtonCenter = Offset(710, 600);
  static const Offset nextButtonCenter = Offset(890, 600);

  @override
  Future<void> onLoad() async {
    // 폭죽: 원 파티클 40개짜리 방사형 버스트를 화면 위쪽 세 곳에서 동시에.
    add(_confettiBurst(Vector2(420, 260)));
    add(_confettiBurst(Vector2(800, 200)));
    add(_confettiBurst(Vector2(1180, 260)));
    add(TextComponent(
      text: S.t('clear'),
      position: Vector2(800, 380),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 96,
          fontWeight: FontWeight.w900,
        ),
      ),
    ));
    add(WinOverlayButton(
      center: retryButtonCenter,
      size: buttonSize,
      draw: _drawRetryIcon,
      onTap: game.resetToEdit,
    ));
    add(WinOverlayButton(
      center: nextButtonCenter,
      size: buttonSize,
      draw: _drawNextIcon,
      onTap: () => game.onNextRequested?.call(),
    ));
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = const Color(0xB0000000),
    );
  }
}

/// One [WinOverlay] action button: filled rounded square with a
/// caller-drawn icon, >=100px per side (shared-contract touch-target
/// minimum for overlay buttons; [WinOverlay.buttonSize] is 140).
///
/// Public (not [WinOverlay]-private) and has no TapCallbacks: [PiyakGame]'s
/// tap-synthesis dispatch needs to recognize this type via componentsAtPoint
/// and invoke [onTap] directly - see piyak_game.dart's "Real-finger tap
/// synthesis" comment for why a real onTapUp is unreachable on this button
/// on a real device.
class WinOverlayButton extends PositionComponent {
  WinOverlayButton({
    required Offset center,
    required double size,
    required this.draw,
    required this.onTap,
  }) : super(
          position: Vector2(center.dx - size / 2, center.dy - size / 2),
          size: Vector2.all(size),
        );

  final void Function(Canvas canvas, Offset center, double radius) draw;
  final VoidCallback onTap;

  @override
  void render(Canvas canvas) {
    _drawStickerCard(canvas, Rect.fromLTWH(0, 0, size.x, size.y), 24, _kCardBg);
    draw(canvas, Offset(size.x / 2, size.y / 2), size.x * 0.28);
  }
}

// 재시도: 반시계 방향 호(300도) + 호 끝에 화살촉. 카드가 크림이라 코랄로
// 그려야 눈에 띈다(다시=코랄, 다음=초록 - RunToggleButton과 같은 팔레트).
void _drawRetryIcon(Canvas canvas, Offset c, double r) {
  final paint = Paint()
    ..color = _kCandyCoralBand
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7;
  const start = -pi * 0.65;
  const sweep = pi * 1.5;
  canvas.drawArc(
      Rect.fromCircle(center: c, radius: r), start, sweep, false, paint);
  final tipAngle = start + sweep;
  final tip = Offset(c.dx + r * cos(tipAngle), c.dy + r * sin(tipAngle));
  canvas.save();
  canvas.translate(tip.dx, tip.dy);
  canvas.rotate(tipAngle + pi / 2);
  final head = Path()
    ..moveTo(0, -12)
    ..lineTo(14, 8)
    ..lineTo(-14, 8)
    ..close();
  canvas.drawPath(head, Paint()..color = _kCandyCoralBand);
  canvas.restore();
}

// 다음: 오른쪽 향 삼각형(재생 버튼과 같은 모양, 맥락상 구별됨).
void _drawNextIcon(Canvas canvas, Offset c, double r) {
  final path = Path()
    ..moveTo(c.dx - r * 0.6, c.dy - r)
    ..lineTo(c.dx - r * 0.6, c.dy + r)
    ..lineTo(c.dx + r, c.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = _kCandyGreenBand);
}

// catalog.dart의 파스텔 팔레트에서 발췌 - 앱 전체와 색감이 일관된다.
const List<Color> _confettiColors = [
  Color(0xFFFF8A80), // pastel coral
  Color(0xFFFFE082), // pastel gold
  Color(0xFF90CAF9), // pastel sky blue
  Color(0xFF80CBC4), // pastel teal
  Color(0xFFCE93D8), // pastel purple
  Color(0xFFFFCC80), // pastel orange
];

/// One confetti burst: 40 circle particles radiating outward from [origin]
/// at random angles/speeds, falling under gravity, gone after 0.9s (Flame's
/// [ParticleSystemComponent] self-removes once its particle's lifespan
/// ends - see that class's own `update`). [WinOverlay.onLoad] fires three
/// of these at once from different points, matching the brief's "2~3회".
ParticleSystemComponent _confettiBurst(Vector2 origin) {
  final rng = Random();
  return ParticleSystemComponent(
    position: origin,
    particle: Particle.generate(
      count: 40,
      lifespan: 0.9,
      generator: (i) {
        final angle = rng.nextDouble() * 2 * pi;
        final speed = 150 + rng.nextDouble() * 250;
        return CircleParticle(
          radius: 3 + rng.nextDouble() * 3,
          paint: Paint()..color = _confettiColors[i % _confettiColors.length],
        ).accelerated(
          acceleration: Vector2(0, 500),
          speed: Vector2(cos(angle), sin(angle)) * speed,
        );
      },
    ),
  );
}

import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:forge2d/forge2d.dart' hide World;

import '../sim/catalog.dart';

/// Meters -> pixels. Fixed resolution 1600x900 = 16x9 world meters * 100.
/// Single source of truth; [PiyakGame.ppm] aliases this same constant.
const double kPpm = 100.0;

/// Placeholder physics-footprint painter for one part.
///
/// Two lifecycles, same visuals:
/// - edit mode: [body] is null, position/angle are fixed at construction
///   (drawn straight from [StageData.preset]/`placements`, no simulation).
/// - run mode: [body] is the forge2d body this view shadows; [update] copies
///   `body.position`/`body.angle` every frame (no axis flip - the sim world
///   is already y-down/top-left-origin, same as screen).
class PartView extends PositionComponent {
  PartView({
    this.body,
    this.part,
    this.preset = '',
    this.platformWidthM = 0,
    required Vector2 posM,
    required double angleRad,
  }) : super(
          position: posM * kPpm,
          angle: angleRad,
          anchor: Anchor.center,
          size: _sizeFor(part, preset, platformWidthM),
        );

  /// null in edit mode (nothing to follow); set in run mode.
  final Body? body;

  /// Catalog part, or null for the three preset-only kinds below.
  final PartType? part;

  /// 'platform' | 'basket' | 'button' | '' (catalog part).
  final String preset;

  /// Only meaningful when preset == 'platform' (stage-configurable width).
  final double platformWidthM;

  late final PartSpec? spec = part == null ? null : Catalog.of(part!);
  late final _Shape _shape = _shapeFor(part, preset);

  late final Paint _fill = Paint()..color = _colorFrom(_colorArgb);
  late final Paint _stroke = Paint()
    ..color = const Color(0x66263238)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  late final Paint _highlight = Paint()..color = const Color(0x99FFFFFF);
  late final Paint _accent = Paint()..color = const Color(0xFF37474F);
  late final Paint _zigzag = Paint()
    ..color = const Color(0xFF37474F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  int get _colorArgb {
    final s = spec;
    if (s != null) return s.color;
    switch (preset) {
      case 'platform':
        return 0xFFA1887F; // pastel taupe (terrain)
      case 'basket':
        return 0xFFFFD54F; // pastel gold (goal object)
      case 'button':
        return 0xFFEF9A9A; // pastel red (goal object)
      default:
        return 0xFFCCCCCC;
    }
  }

  static Color _colorFrom(int argb) => Color(argb);

  // run mode only: edit-mode views (body == null) stay exactly where they
  // were constructed.
  @override
  void update(double dt) {
    final b = body;
    if (b != null) {
      position = b.position * kPpm;
      angle = b.angle;
    }
  }

  @override
  void render(Canvas canvas) {
    switch (_shape) {
      case _Shape.ball:
        _renderBall(canvas);
      case _Shape.box:
        _renderBox(canvas);
      case _Shape.gear:
        _renderGear(canvas);
      case _Shape.seesaw:
        _renderSeesaw(canvas);
      case _Shape.balloon:
        _renderBalloon(canvas);
      case _Shape.fan:
        _renderFan(canvas);
      case _Shape.trampoline:
        _renderTrampoline(canvas);
      case _Shape.tack:
        _renderTack(canvas);
      case _Shape.basket:
        _renderBasket(canvas);
      case _Shape.button:
        _renderButton(canvas);
    }
  }

  /// Body-local meters (origin = body center) -> local render-space pixels
  /// (origin = this component's top-left, per PositionComponent's
  /// anchor-independent render() convention).
  Offset _p(double xM, double yM) =>
      Offset(size.x / 2 + xM * kPpm, size.y / 2 + yM * kPpm);

  (double, double) get _boxHalfExtentsM {
    if (preset == 'platform') return (platformWidthM / 2, 0.2);
    final s = spec!;
    return (s.w! / 2, s.h! / 2);
  }

  void _renderBall(Canvas canvas) {
    final r = spec!.radius! * kPpm;
    final c = _p(0, 0);
    canvas.drawCircle(c, r, _fill);
    canvas.drawCircle(c, r, _stroke);
    canvas.drawCircle(
        Offset(c.dx - r * 0.35, c.dy - r * 0.35), r * 0.3, _highlight);
  }

  void _renderBox(Canvas canvas) {
    final (hw, hh) = _boxHalfExtentsM;
    final rect = Rect.fromCenter(
        center: _p(0, 0), width: hw * 2 * kPpm, height: hh * 2 * kPpm);
    final rr = RRect.fromRectAndRadius(
        rect, Radius.circular(min(hw, hh) * kPpm * 0.35));
    canvas.drawRRect(rr, _fill);
    canvas.drawRRect(rr, _stroke);
  }

  void _renderGear(Canvas canvas) {
    final r = spec!.radius! * kPpm;
    final c = _p(0, 0);
    if (part == PartType.paddleGear) {
      final barRect = Rect.fromCenter(
          center: c, width: spec!.w! * kPpm, height: spec!.h! * kPpm);
      canvas.drawRect(barRect, _accentFill);
      canvas.drawRect(barRect, _stroke);
    }
    canvas.drawCircle(c, r, _fill);
    canvas.drawCircle(c, r, _stroke);
    const teeth = 8;
    final toothLen = r * 0.3;
    final toothW = r * 0.24;
    for (var i = 0; i < teeth; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * (2 * pi / teeth));
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(r + toothLen / 2, 0),
            width: toothLen,
            height: toothW),
        _fill,
      );
      canvas.restore();
    }
    // Rotation indicator: fixed local offset, so it visibly sweeps around
    // the center as `angle` (synced from body.angle) changes.
    canvas.drawCircle(Offset(c.dx + r * 0.55, c.dy), r * 0.15, _accent);
  }

  late final Paint _accentFill = Paint()..color = const Color(0xFF546E7A);

  void _renderSeesaw(Canvas canvas) {
    final hw = spec!.w! / 2 * kPpm;
    final hh = spec!.h! / 2 * kPpm;
    final c = _p(0, 0);
    final rect =
        Rect.fromCenter(center: c, width: hw * 2, height: hh * 2);
    canvas.drawRect(rect, _fill);
    canvas.drawRect(rect, _stroke);
    // Triangle pivot stand, apex at the bar's own center (the real pivot
    // point - matches sim_world's revolute anchor at body.worldCenter).
    final path = Path()
      ..moveTo(c.dx, c.dy + hh)
      ..lineTo(c.dx - hh * 2.2, c.dy + hh * 5)
      ..lineTo(c.dx + hh * 2.2, c.dy + hh * 5)
      ..close();
    canvas.drawPath(path, _accentFill);
    canvas.drawPath(path, _stroke);
  }

  void _renderBalloon(Canvas canvas) {
    final rx = spec!.radius! * kPpm * 0.85;
    final ry = spec!.radius! * kPpm * 1.05;
    final c = _p(0, 0);
    final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    canvas.drawOval(rect, _fill);
    canvas.drawOval(rect, _stroke);
    canvas.drawLine(Offset(c.dx, c.dy + ry),
        Offset(c.dx, c.dy + ry + spec!.radius! * kPpm * 0.6), _stroke);
    canvas.drawCircle(
        Offset(c.dx - rx * 0.3, c.dy - ry * 0.35), rx * 0.25, _highlight);
  }

  void _renderFan(Canvas canvas) {
    final hw = spec!.w! / 2 * kPpm;
    final hh = spec!.h! / 2 * kPpm;
    final c = _p(0, 0);
    final rect =
        Rect.fromCenter(center: c, width: hw * 2, height: hh * 2);
    canvas.drawRect(rect, _fill);
    canvas.drawRect(rect, _stroke);
    // 3 wind lines off the local +x face - matches the physics wind zone's
    // own direction (fan pushes along its own local +x, see SimWorld._FanZone).
    for (var i = -1; i <= 1; i++) {
      final y = c.dy + i * hh * 0.5;
      canvas.drawLine(
          Offset(c.dx + hw, y), Offset(c.dx + hw + hh * 1.4, y), _stroke);
    }
  }

  void _renderTrampoline(Canvas canvas) {
    final hw = spec!.w! / 2 * kPpm;
    final hh = spec!.h! / 2 * kPpm;
    final c = _p(0, 0);
    final rect =
        Rect.fromCenter(center: c, width: hw * 2, height: hh * 2);
    canvas.drawRect(rect, _fill);
    canvas.drawRect(rect, _stroke);
    const zigzags = 6;
    final path = Path()..moveTo(c.dx - hw, c.dy);
    for (var i = 1; i <= zigzags; i++) {
      final x = c.dx - hw + (hw * 2) * i / zigzags;
      final y = c.dy + (i.isOdd ? -hh * 0.7 : hh * 0.7);
      path.lineTo(x, y);
    }
    canvas.drawPath(path, _zigzag);
  }

  void _renderTack(Canvas canvas) {
    final r = spec!.radius! * kPpm * 1.6; // small sensor - scale up to read
    final c = _p(0, 0);
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx - r, c.dy + r)
      ..lineTo(c.dx + r, c.dy + r)
      ..close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
  }

  // Exact local offsets from SimWorld._buildBasket (floor + 2 walls) so the
  // "U" placeholder lines up with the physics fixtures it stands in for.
  void _renderBasket(Canvas canvas) {
    _rectAt(canvas, 0, 0.36, 0.5, 0.06);
    _rectAt(canvas, -0.44, 0, 0.06, 0.3);
    _rectAt(canvas, 0.44, 0, 0.06, 0.3);
  }

  void _rectAt(
      Canvas canvas, double xM, double yM, double halfWM, double halfHM) {
    final rect = Rect.fromCenter(
        center: _p(xM, yM), width: halfWM * 2 * kPpm, height: halfHM * 2 * kPpm);
    canvas.drawRect(rect, _fill);
    canvas.drawRect(rect, _stroke);
  }

  // Half-round dome centered on the button's own origin (physics box is
  // only 0.22m tall, so the offset from true center is negligible for a
  // placeholder).
  void _renderButton(Canvas canvas) {
    final r = 0.4 * kPpm;
    final c = _p(0, 0);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, pi, pi, true, _fill);
    canvas.drawArc(rect, pi, pi, true, _stroke);
  }

  static Vector2 _sizeFor(
      PartType? part, String preset, double platformWidthM) {
    if (preset == 'platform') {
      return Vector2(platformWidthM * kPpm, 0.4 * kPpm);
    }
    if (preset == 'basket') return Vector2(1.0 * kPpm, 0.72 * kPpm);
    if (preset == 'button') return Vector2(0.8 * kPpm, 0.22 * kPpm);
    final s = Catalog.of(part!);
    if (s.radius != null) return Vector2.all(2 * s.radius! * kPpm);
    return Vector2(s.w! * kPpm, s.h! * kPpm);
  }

  static _Shape _shapeFor(PartType? part, String preset) {
    switch (preset) {
      case 'platform':
        return _Shape.box;
      case 'basket':
        return _Shape.basket;
      case 'button':
        return _Shape.button;
    }
    switch (part!) {
      case PartType.plank:
      case PartType.domino:
        return _Shape.box;
      case PartType.rubberBall:
      case PartType.metalBall:
        return _Shape.ball;
      case PartType.balloon:
        return _Shape.balloon;
      case PartType.seesaw:
        return _Shape.seesaw;
      case PartType.motorGear:
      case PartType.gear:
      case PartType.paddleGear:
        return _Shape.gear;
      case PartType.fan:
        return _Shape.fan;
      case PartType.trampoline:
        return _Shape.trampoline;
      case PartType.tack:
        return _Shape.tack;
    }
  }
}

enum _Shape { ball, box, gear, seesaw, balloon, fan, trampoline, tack, basket, button }

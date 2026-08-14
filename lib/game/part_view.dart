import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
// forge2d also exports its own unrelated `Particle` (its box2d particle-fluid
// system, never used by this game) - hide it so flame's rendering `Particle`
// (used by _spawnDustPuff below) resolves unambiguously.
import 'package:forge2d/forge2d.dart' hide World, Particle;

import '../sim/catalog.dart';

/// Meters -> pixels. Fixed resolution 1600x900 = 16x9 world meters * 100.
/// Single source of truth; [PiyakGame.ppm] aliases this same constant.
const double kPpm = 100.0;

/// Bundled asset paths (pubspec-declared, full path e.g.
/// "assets/images/parts/plank.png"), loaded once per process and memoized -
/// every [PartView]/background `onLoad` awaits this same [Future] instead of
/// each re-parsing `AssetManifest.bin` on its own (there can be dozens of
/// PartViews rebuilt per mode switch, see `PiyakGame._rebuildViews`).
Future<Set<String>>? _manifestFuture;
Future<Set<String>> loadAssetManifestPaths() {
  return _manifestFuture ??= AssetManifest.loadFromAssetBundle(rootBundle)
      .then((m) => m.listAssets().toSet());
}

/// Sprite path (relative to Flame's default `assets/images/` prefix) for a
/// part/preset's art. 'platform' points at an optional TILE texture
/// (`platform_tile.png`, drawn by [PartView._renderPlatformTile] - not part
/// of the original 14-file docs/art-request.md contract, added later as a
/// juice pass); every other preset/part has one of the original 14. Absence
/// is handled uniformly downstream regardless of which case it is: if the
/// manifest doesn't have the file yet, [PartView.onLoad] just never sets
/// `_sprite`, so `render()` silently falls back to a code-drawn shape.
String? _spriteRelPath(PartType? part, String preset) {
  if (preset == 'platform') return 'parts/platform_tile.png';
  if (preset == 'basket') return 'parts/basket.png';
  if (preset == 'button') return 'parts/button.png';
  if (part == null) return null;
  return 'parts/${jsonIdOf(part)}.png';
}

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
    this.ghostColor,
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

  /// Non-null turns every paint (fill/stroke/highlight/accent) into this one
  /// translucent color, overriding the catalog/preset palette - used by the
  /// drag-placement ghost (lib/game/hud.dart) so any part type gets a
  /// uniform "can I drop here" green/red silhouette for free, reusing this
  /// class's existing per-shape render methods instead of duplicating them.
  final Color? ghostColor;

  late final PartSpec? spec = part == null ? null : Catalog.of(part!);
  late final _Shape _shape = _shapeFor(part, preset);

  Sprite? _sprite;

  /// True once a bundled sprite has been resolved for this part/preset -
  /// false forever if the shape has no sprite slot (platform) or the art
  /// file isn't in the asset bundle yet. Exposed for
  /// test/game/sprite_fallback_test.dart.
  bool get hasSprite => _sprite != null;

  @override
  Future<void> onLoad() async {
    final relPath = _spriteRelPath(part, preset);
    if (relPath == null) return;
    final manifest = await loadAssetManifestPaths();
    if (!manifest.contains('assets/images/$relPath')) return;
    _sprite = await Sprite.load(relPath);
  }

  late final Paint _fill = Paint()..color = ghostColor ?? _colorFrom(_colorArgb);
  late final Paint _stroke = Paint()
    ..color = ghostColor?.withAlpha(220) ?? const Color(0x66263238)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  late final Paint _highlight = Paint()..color = ghostColor ?? const Color(0x99FFFFFF);
  late final Paint _accent = Paint()..color = ghostColor ?? const Color(0xFF37474F);
  late final Paint _zigzag = Paint()
    ..color = ghostColor ?? const Color(0xFF37474F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  // 목재 발판 전용 색(_renderPlatform) - platform은 절대 고스트로 렌더되지
  // 않으므로(트레이는 PartType만 드래그하고 platform은 preset 전용) 아래
  // ghostColor 분기는 실제로는 안 타지만, 이 파일의 다른 모든 Paint 필드와
  // 문체를 맞추기 위해 그대로 남긴다.
  late final Paint _platformFill =
      Paint()..color = ghostColor ?? const Color(0xFFC68958);
  late final Paint _platformBand =
      Paint()..color = ghostColor ?? const Color(0xFFB07A48);
  late final Paint _platformGrain = Paint()
    ..color = ghostColor?.withAlpha(160) ?? const Color(0x334E342E)
    ..strokeWidth = 2;
  late final Paint _platformStroke = Paint()
    ..color = ghostColor ?? const Color(0xFF4E342E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;

  // 소프트 그림자 - 모든 도형/스프라이트 공용 (_renderShadow).
  late final Paint _shadowPaint = Paint()..color = const Color(0x2E000000);
  static const double kShadowHeight = 12;

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
      _trackImpact(b);
      _updateSquash(dt);
    }
    final t = _pulseElapsedS;
    if (t != null) {
      const total = kPulseCycleSeconds * kPulseCycles;
      final next = t + dt;
      if (next >= total) {
        _pulseElapsedS = null;
        scale = Vector2.all(1);
      } else {
        _pulseElapsedS = next;
        final bump =
            kPulseScaleBump * sin(pi * next / kPulseCycleSeconds).abs();
        scale = Vector2.all(1 + bump);
      }
    }
  }

  // Non-null only when ghostColor is set AND a sprite loaded - collapses the
  // sprite to a flat silhouette in ghostColor, the sprite equivalent of how
  // every vector _render* method already swaps its Paint's color for
  // ghostColor (see class doc comment on ghostColor).
  late final Paint? _spriteGhostPaint = ghostColor == null
      ? null
      : (Paint()..colorFilter = ColorFilter.mode(ghostColor!, BlendMode.srcIn));

  // 목표물 강조 펄스(piyak_game.dart의 PiyakGame.triggerGoalPulse가 목표
  // 오브젝트의 PartView에만 호출) - 초/재시작 시각적 신호로 스케일을
  // 1.0<->1.0+kPulseScaleBump 사이에서 두 번 오간다. null이면 펄스 중이
  // 아님(목표물이 아닌 PartView는 pulse()가 아예 호출되지 않으므로 평생
  // null). 컴포넌트 자체의 transform(scale)만 건드리므로 위 body-sync
  // 분기의 position/angle과 절대 충돌하지 않는다 - 펄스는 항상 에딧 모드
  // 진입 순간에만 트리거되고(triggerGoalPulse의 mode 가드), 그 순간의
  // PartView는 body가 없는 정적 에딧 뷰이기 때문.
  double? _pulseElapsedS;
  static const double kPulseCycleSeconds = 0.4;
  static const int kPulseCycles = 2;
  static const double kPulseScaleBump = 0.15;

  /// 펄스를 (재)시작한다 - [PiyakGame.triggerGoalPulse]만 호출.
  void pulse() => _pulseElapsedS = 0;

  // 충돌 손맛(오너 플레이테스트: "물리 손맛이 없다") - run 모드에서만(아래
  // _trackImpact가 update()의 `if (b != null)` 분기에서만 호출됨) 몸체
  // 속도의 프레임 간 변화량을 본다. 정적 바디(플랫폼/바구니/버튼/부채/
  // 트램펄린/압정)는 velocity가 항상 0이라 _trackImpact의 dynamic 가드에서
  // 걸러진다. 이 인스턴스가 평생 run 모드(body!=null)로만 존재하는 한
  // 위의 펄스([_pulseElapsedS])는 triggerGoalPulse의 edit-only 게이트 때문에
  // 절대 트리거되지 않으므로, 스쿼시와 펄스가 같은 `scale`을 동시에 다투는
  // 일은 없다 - 뼈대(경과시간 필드 + update()에서 진행)만 재사용한다.
  Vector2? _lastVelocity;
  double? _squashElapsedS;
  static const double kImpactSpeedThreshold = 3.0; // m/s
  static const double kSquashDurationS = 0.14;
  static const double kSquashScaleBump = 0.12;
  static const double kDustLifespanS = 0.35;
  static const List<Color> _kDustColors = [
    Color(0xFFF5EEDD), // beige
    Color(0xFFFFFFFF), // white
  ];

  // body.linearVelocity는 매 프레임 같은 Vector2 인스턴스를 제자리에서
  // 수정한다(forge2d Body 소스로 확인함: `final Vector2 linearVelocity =
  // Vector2.zero()`에 setFrom/+=로 누적) - clone() 없이 저장하면 다음 프레임
  // 비교가 항상 자기 자신과의 차이(0)가 되어 스쿼시가 영원히 트리거되지
  // 않는다.
  void _trackImpact(Body b) {
    if (b.bodyType != BodyType.dynamic) return;
    final v = b.linearVelocity;
    final last = _lastVelocity;
    _lastVelocity = v.clone();
    if (last != null && (v - last).length >= kImpactSpeedThreshold) {
      _squashElapsedS = 0;
      _spawnDustPuff();
    }
  }

  // 착지/충돌 스쿼시: 즉시 찌그러진 스케일로 튀고 kSquashDurationS에 걸쳐
  // 정확히 1.0으로 스프링백. 화면축 고정(충돌 법선 계산 없음 - 명세대로
  // 단순하게: 회전 중인 부품이면 스쿼시도 그 회전을 그대로 타고 돈다는
  // 뜻이지만, 지속 시간이 140ms뿐이라 실사용에서 거슬리지 않는다).
  void _updateSquash(double dt) {
    final t = _squashElapsedS;
    if (t == null) return;
    final next = t + dt;
    if (next >= kSquashDurationS) {
      _squashElapsedS = null;
      scale = Vector2.all(1);
      return;
    }
    _squashElapsedS = next;
    final decay = 1 - next / kSquashDurationS;
    scale =
        Vector2(1 + kSquashScaleBump * decay, 1 - kSquashScaleBump * decay);
  }

  // 흙먼지 퍼프: 짧게 사는 원 파티클 6~10개. 이 PartView 자신이 아니라
  // parent(=world - PiyakGame._rebuildViews가 이 컴포넌트를 world.add로
  // 붙이므로 마운트 후 parent는 항상 world)에 형제로 추가한다: 이 뷰의
  // 자식으로 붙이면 스쿼시 스케일/바디 회전을 그대로 상속해 먼지구름까지
  // 같이 찌그러지고 돈다. 수명이 다하면 flame의 ParticleSystemComponent가
  // 스스로 제거한다(hud.dart 폭죽과 동일 메커니즘) - 따로 치울 코드가
  // 필요 없다.
  void _spawnDustPuff() {
    final rng = Random();
    parent?.add(ParticleSystemComponent(
      position: position.clone(),
      particle: Particle.generate(
        count: 6 + rng.nextInt(5),
        lifespan: kDustLifespanS,
        generator: (i) {
          final a = rng.nextDouble() * 2 * pi;
          final speed = 30 + rng.nextDouble() * 60;
          return CircleParticle(
            radius: 2 + rng.nextDouble() * 2,
            paint: Paint()
              ..color = _kDustColors[rng.nextInt(_kDustColors.length)],
          ).accelerated(
            acceleration: Vector2(0, 60),
            speed: Vector2(cos(a), sin(a)) * speed,
          );
        },
      ),
    ));
  }

  @override
  void render(Canvas canvas) {
    _renderShadow(canvas);
    final sprite = _sprite;
    if (sprite != null) {
      if (preset == 'platform') {
        _renderPlatformTile(canvas, sprite);
        return;
      }
      // 1.05x the physics footprint (this component's own `size`, unchanged
      // by sprite presence) - slightly larger so the art's own outline hides
      // the physics silhouette instead of visibly clipping inside it.
      final rect = Rect.fromCenter(
        center: Offset(size.x / 2, size.y / 2),
        width: size.x * 1.05,
        height: size.y * 1.05,
      );
      sprite.renderRect(canvas, rect, overridePaint: _spriteGhostPaint);
      return;
    }
    switch (_shape) {
      case _Shape.ball:
        _renderBall(canvas);
      case _Shape.box:
        _renderBox(canvas);
      case _Shape.platform:
        _renderPlatform(canvas);
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

  // 소프트 그림자 - 모든 부품이 배경 위에 붕 뜬 것처럼 보이는 문제(오너
  // 피드백 "공간감이 없다")의 최소 대응. 광원 계산 없이 고정 오프셋 타원
  // 하나만 발밑에 깐다. 풍선은 날아다니는 오브젝트라 제외(그림자 없음 -
  // 명세의 "your call" 선택). 고스트 프리뷰(드래그 중 미리보기)도 제외 -
  // 아직 놓이지 않은 부품에 그림자는 과함.
  void _renderShadow(Canvas canvas) {
    if (ghostColor != null || part == PartType.balloon) return;
    final rect = Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2 + kShadowHeight / 2 + 2),
      width: size.x * 0.9,
      height: kShadowHeight,
    );
    canvas.drawOval(rect, _shadowPaint);
  }

  /// Body-local meters (origin = body center) -> local render-space pixels
  /// (origin = this component's top-left, per PositionComponent's
  /// anchor-independent render() convention).
  Offset _p(double xM, double yM) =>
      Offset(size.x / 2 + xM * kPpm, size.y / 2 + yM * kPpm);

  // platform은 이제 자기 전용 _Shape.platform/_renderPlatform을 타므로
  // (더 이상 _Shape.box가 아님 - _shapeFor 참고) 여기선 항상 catalog part다.
  (double, double) get _boxHalfExtentsM {
    final s = spec!;
    return (s.w! / 2, s.h! / 2);
  }

  /// Off-center roll-visibility marker position (local render-space offset
  /// from this component's own center), ball shapes only - null otherwise.
  /// Exposed for test/game/part_view_juice_test.dart (asserts the marker is
  /// configured without a full pixel render).
  Offset? get rollMarkerOffset => _shape == _Shape.ball
      ? Offset(spec!.radius! * kPpm * kRollMarkerOffsetFrac, 0)
      : null;

  static const double kRollMarkerOffsetFrac = 0.6;
  static const double kRollMarkerRadiusFrac = 0.16;

  void _renderBall(Canvas canvas) {
    final r = spec!.radius! * kPpm;
    final c = _p(0, 0);
    canvas.drawCircle(c, r, _fill);
    canvas.drawCircle(c, r, _stroke);
    canvas.drawCircle(
        Offset(c.dx - r * 0.35, c.dy - r * 0.35), r * 0.3, _highlight);
    // 굴러가는 느낌(오너 피드백: "물리 손맛이 없다") - 몸체 회전이 눈에
    // 보이도록 중심에서 벗어난 점 하나. _renderGear의 회전 표시자와 정확히
    // 같은 아이디어: 로컬 고정 오프셋이라 angle(=body.angle)이 바뀔 때마다
    // 화면에서 실제로 돈다. 패턴 아트가 들어오면 그쪽이 자연히 이 역할을
    // 대신하겠지만, 그때도 도형 폴백/아트 공백 상황엔 이게 남아 있어야 한다.
    canvas.drawCircle(
        c + rollMarkerOffset!, r * kRollMarkerRadiusFrac, _accent);
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

  // 목재 발판(오너 피드백: "공간감이 없다" - 밋밋한 회색 막대가 배경과 안
  // 어울림). 스티커 재질 언어(hud.dart의 초콜릿 외곽선 + 크림 카드)와 맞춘
  // 코드 패턴: 따뜻한 나무색 채움 + 초콜릿 외곽선 + 살짝 어두운 상단 밴드
  // (광원 계산 없는 고정 하이라이트) + 결 무늬 2~3줄, 둥근 모서리.
  void _renderPlatform(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    // 8px 고정 - size.y*0.3(아래 밴드 두께)과 같은 값을 우연히 재사용하면
    // 40px 높이 막대가 알약처럼 보일 만큼 과하게 둥글어진다.
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rr, _platformFill);
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, size.y * 0.3),
      _platformBand,
    );
    for (final frac in [0.35, 0.55, 0.75]) {
      final y = rect.top + rect.height * frac;
      canvas.drawLine(
          Offset(rect.left, y), Offset(rect.right, y), _platformGrain);
    }
    canvas.restore();
    canvas.drawRRect(rr, _platformStroke);
  }

  // 선택적 타일 스프라이트(art-request.md 14종에는 없는 손맛 패스 전용 -
  // `_spriteRelPath`의 doc comment 참고): 발판 높이에 맞춰 스케일한 타일을
  // 폭 전체에 반복해서 그린다. 마지막 타일이 발판 폭을 넘치면 clipRect로
  // 잘라내는 쪽이 소스 rect를 부분적으로 잘라 스케일하는 것보다 타일마다
  // 결 무늬 스케일이 어긋나지 않아 더 낫다.
  void _renderPlatformTile(Canvas canvas, Sprite sprite) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final srcSize = sprite.originalSize;
    final tileW = srcSize.x * (rect.height / srcSize.y);
    canvas.save();
    canvas.clipRect(rect);
    for (var x = 0.0; x < rect.width; x += tileW) {
      sprite.renderRect(canvas, Rect.fromLTWH(x, 0, tileW, rect.height));
    }
    canvas.restore();
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

  late final Paint _accentFill = Paint()..color = ghostColor ?? const Color(0xFF546E7A);

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
        return _Shape.platform;
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

enum _Shape {
  ball,
  box,
  platform,
  gear,
  seesaw,
  balloon,
  fan,
  trampoline,
  tack,
  basket,
  button
}

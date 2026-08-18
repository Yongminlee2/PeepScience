import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/hud.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/stage_data.dart';
import 'package:piyak_science/ui/strings.dart';

import '../sim/helpers.dart';

/// Same bounded-pump bootstrap as run_flow_test.dart - see that file's own
/// comment for why a plain t.pump() loop (not game.ready()) is required
/// under flutter_test's FakeAsync. Every component asserted on below sets
/// position/size synchronously in its own constructor (super(position:,
/// size:)), so unlike goal_pulse_test.dart this never needs to wait on a
/// real sprite decode.
Future<PiyakGame> _pumpGame(WidgetTester t, StageData s) async {
  t.view.physicalSize = const Size(1600, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final game = PiyakGame(s);
  await t.pumpWidget(GameWidget(game: game));
  for (var i = 0; i < 10; i++) {
    await t.pump();
  }
  return game;
}

Rect _rectOf(PositionComponent c) =>
    Rect.fromLTWH(c.position.x, c.position.y, c.size.x, c.size.y);

/// Trivially-valid base stage (basket goal, one ball) - only `feature`/
/// `challenge`/`prediction` vary per test, same pattern as run_flow_test.dart's
/// 예측+도전 test building on top of `_trivialStage()`.
StageData _baseStage() => stage(
  '{"type":"basket","x":8,"y":6,"angle":0}',
  '{"type":"rubber_ball","count":1}',
  '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
);

StageData _withFeatures(
  StageData base, {
  StageFeature? feature,
  ChallengeSpec? challenge,
  PredictionSpec? prediction,
}) => StageData(
  id: base.id,
  world: base.world,
  index: base.index,
  goal: base.goal,
  preset: base.preset,
  tray: base.tray,
  solution: base.solution,
  feature: feature,
  challenge: challenge,
  prediction: prediction,
);

void main() {
  testWidgets('연쇄 반응 + 도전 스테이지는 두 리본이 겹치지 않게 세로로 쌓인다', (t) async {
    final s = _withFeatures(
      _baseStage(),
      feature: StageFeature.chainReaction,
      challenge: const ChallengeSpec(partLimit: 2),
    );
    final game = await _pumpGame(t, s);

    final chain = game.camera.viewport.children
        .whereType<ChainReactionRibbon>()
        .single;
    final challenge = game.camera.viewport.children
        .whereType<ChallengeRibbon>()
        .single;
    final goal = game.camera.viewport.children.whereType<GoalBadge>().single;
    final runButton = game.camera.viewport.children
        .whereType<RunToggleButton>()
        .single;

    // 연쇄 리본 자리는 그대로 - 단일 리본 스테이지와 픽셀 동일해야 한다.
    expect(chain.position, Vector2(_kExpectedRibbonLeft, _kExpectedRibbonTop));

    final chainRect = _rectOf(chain);
    final challengeRect = _rectOf(challenge);
    expect(
      chainRect.overlaps(challengeRect),
      isFalse,
      reason: '두 리본이 (136,20)에 그대로 겹쳐 있으면 안 된다 - 세로 스택 배치 필요',
    );
    // 옆으로 피한 게 아니라 진짜 아래로 쌓였는지 확인.
    expect(challenge.position.x, chain.position.x);
    expect(challenge.position.y, greaterThanOrEqualTo(chainRect.bottom));

    expect(chainRect.overlaps(_rectOf(goal)), isFalse);
    expect(challengeRect.overlaps(_rectOf(goal)), isFalse);
    expect(chainRect.overlaps(_rectOf(runButton)), isFalse);
    expect(challengeRect.overlaps(_rectOf(runButton)), isFalse);
  });

  testWidgets('도전 + 예측 스테이지는 실행 전에도 부품 제한 리본이 보인다', (t) async {
    final s = _withFeatures(
      _baseStage(),
      challenge: const ChallengeSpec(partLimit: 1),
      prediction: const PredictionSpec(answer: PartType.metalBall),
    );
    final game = await _pumpGame(t, s);

    final challengeRibbons = game.camera.viewport.children
        .whereType<ChallengeRibbon>();
    expect(
      challengeRibbons.length,
      1,
      reason: '2번째 별 조건(부품 제한)이 예측 패널에 가려 안 보이면 안 된다',
    );

    final prediction = game.camera.viewport.children
        .whereType<PredictionPanel>()
        .single;
    expect(
      _rectOf(challengeRibbons.single).overlaps(_rectOf(prediction)),
      isFalse,
    );
  });

  testWidgets('연쇄 반응만 있는 스테이지는 리본 위치가 그대로다', (t) async {
    final s = _withFeatures(_baseStage(), feature: StageFeature.chainReaction);
    final game = await _pumpGame(t, s);

    final chain = game.camera.viewport.children
        .whereType<ChainReactionRibbon>()
        .single;
    expect(chain.position, Vector2(_kExpectedRibbonLeft, _kExpectedRibbonTop));
    expect(
      game.camera.viewport.children.whereType<ChallengeRibbon>(),
      isEmpty,
    );
  });

  testWidgets('도전만 있는 스테이지는 리본 위치가 그대로다', (t) async {
    final s = _withFeatures(
      _baseStage(),
      challenge: const ChallengeSpec(partLimit: 1),
    );
    final game = await _pumpGame(t, s);

    final challenge = game.camera.viewport.children
        .whereType<ChallengeRibbon>()
        .single;
    expect(
      challenge.position,
      Vector2(_kExpectedRibbonLeft, _kExpectedRibbonTop),
    );
    expect(
      game.camera.viewport.children.whereType<ChainReactionRibbon>(),
      isEmpty,
    );
  });

  // 실기기 검수 회귀 방지: 회전 손잡이는 널빤지·선풍기에만 붙는데, 트레이에
  // 그런 부품이 없는 판(100판 중 39판)에서도 "노란 손잡이로 돌린 뒤"라고
  // 안내하고 있었다. 아이가 있지도 않은 손잡이를 찾게 된다.
  List<String> trayTexts(PiyakGame game) => game.camera.viewport.children
      .whereType<TrayBar>()
      .single
      .children
      .whereType<TextComponent>()
      .map((c) => c.text)
      .toList();

  testWidgets('회전 가능한 부품이 없는 판은 손잡이를 언급하지 않는 힌트를 쓴다', (t) async {
    final s = stage(
      '{"type":"basket","x":8,"y":6,"angle":0}',
      '{"type":"trampoline","count":1}', // 트램펄린은 회전 불가
      '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
    );
    final game = await _pumpGame(t, s);

    expect(trayTexts(game), contains(S.t('dragHintNoTurn')));
    expect(trayTexts(game), isNot(contains(S.t('dragHint'))));
  });

  testWidgets('회전 가능한 부품이 있으면 손잡이 안내를 그대로 쓴다', (t) async {
    final s = stage(
      '{"type":"basket","x":8,"y":6,"angle":0}',
      '{"type":"plank","count":1}',
      '{"type":"rubber_ball","x":8,"y":2,"angle":0}',
    );
    final game = await _pumpGame(t, s);

    expect(trayTexts(game), contains(S.t('dragHint')));
  });
}

// hud.dart의 _kRibbonLeft/_kRibbonTop은 private - 회귀 방지를 위해 여기서
// 같은 값을 독립적으로 명시한다(GoalBadge.margin처럼 public 상수가 아니므로).
const double _kExpectedRibbonLeft = 136;
const double _kExpectedRibbonTop = 20;

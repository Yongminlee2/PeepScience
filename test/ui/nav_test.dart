import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:piyak_science/game/hud.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/main.dart';
import 'package:piyak_science/services/progress.dart';
import 'package:piyak_science/services/stage_loader.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/stage_data.dart';
import 'package:piyak_science/ui/game_screen.dart';
import 'package:piyak_science/ui/home_screen.dart';
import 'package:piyak_science/ui/strings.dart';

/// Trivially-clearable stage tagged with [id]: a rubber ball starts high
/// above a basket with nothing in the way (same shape as
/// test/game/run_flow_test.dart's own `_trivialStage`, just with a
/// parameterized id - this file needs two distinct ids to exercise
/// stage-to-stage advancement).
StageData _trivialStage(String id) => StageData.fromJson(
  jsonDecode(
        '{"id":"$id","world":1,"index":1,'
        '"goal":{"type":"ball_in_basket"},'
        '"preset":[{"type":"basket","x":8,"y":6,"angle":0}],'
        '"tray":[{"type":"rubber_ball","count":1}],'
        '"solution":[{"type":"rubber_ball","x":8,"y":2,"angle":0}]}',
      )
      as Map<String, dynamic>,
);

StageData _buttonStage(String id) => StageData.fromJson(
  jsonDecode(
        '{"id":"$id","world":1,"index":3,'
        '"goal":{"type":"press_button"},'
        '"preset":[{"type":"button","x":8,"y":6,"angle":0}],'
        '"tray":[{"type":"metal_ball","count":1}],'
        '"solution":[{"type":"metal_ball","x":8,"y":2,"angle":0}]}',
      )
      as Map<String, dynamic>,
);

Future<void> _setSize(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

// RunToggleButton's on-screen center, derived from its own layout constants
// (not duplicated magic numbers) - same approach as run_flow_test.dart's
// own _runButtonCenter.
const Offset _runButtonCenter = Offset(
  1600 - RunToggleButton.margin - RunToggleButton.buttonDiameter / 2,
  900 -
      TrayBar.barHeight -
      RunToggleButton.margin -
      RunToggleButton.buttonDiameter / 2,
);

/// Taps and pumps past flame's MultiTapGestureRecognizer long-tap timer -
/// same as run_flow_test.dart's own `_tap`.
Future<void> _tap(WidgetTester t, Offset pos) async {
  await t.tapAt(pos);
  await t.pump(const Duration(milliseconds: 350));
}

/// Bounded pump loop until `game.sim!.cleared` - NOT pumpAndSettle, which
/// deadlocks once a live PiyakGame is mounted (its ticker never "settles" -
/// see run_flow_test.dart's own comment on the game.ready()/FakeAsync trap).
Future<void> _pumpUntilCleared(
  WidgetTester t,
  PiyakGame game, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps && game.sim?.cleared != true; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
}

/// Bounded settle for a screen that has (or may soon have) a live
/// PiyakGame mounted - pumpAndSettle is unsafe there (see above).
Future<void> _pumpBounded(WidgetTester t, {int times = 15}) async {
  for (var i = 0; i < times; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'tutorial_seen_v1': true});
    AppLang().value = 'system';
  });

  testWidgets('홈 화면에 월드 카드 5개가 렌더된다', (t) async {
    await _setSize(t, const Size(2200, 900));
    await t.pumpWidget(const PiyakScienceApp());
    await t.pumpAndSettle();

    expect(find.text(S.t('world1')), findsOneWidget);
    expect(find.text(S.t('world2')), findsOneWidget);
    expect(find.text(S.t('world3')), findsOneWidget);
    expect(find.text(S.t('world4')), findsOneWidget);
    expect(find.text(S.t('world5')), findsOneWidget);
  });

  testWidgets('잠긴 스테이지 칸을 탭해도 화면이 전환되지 않는다', (t) async {
    await _setSize(t, const Size(2000, 900));
    await t.pumpWidget(const PiyakScienceApp());
    await t.pumpAndSettle();

    // w1_s02: 아무것도 클리어되지 않았고 첫 스테이지도 아니므로 잠김.
    await t.tap(find.byKey(const ValueKey('cell_w1_s02')));
    await t.pump(const Duration(milliseconds: 350));

    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('첫 스테이지 첫 방문에는 4단계 안내가 뜨고 완료 후 도움말로 다시 연다', (t) async {
    SharedPreferences.setMockInitialValues({});
    AppLang().value = 'ko';
    await _setSize(t, const Size(780, 360));
    await t.pumpWidget(
      MaterialApp(
        home: GameScreen(
          stageId: 'w1_s01',
          initialStage: _trivialStage('w1_s01'),
        ),
      ),
    );
    await _pumpBounded(t);

    expect(find.byKey(const ValueKey('tutorial_overlay')), findsOneWidget);
    expect(find.text(S.t('tutorialGoalTitle')), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith('basket.png'),
      ),
      findsOneWidget,
    );

    await t.tap(find.byKey(const ValueKey('tutorial_next')));
    await t.pump(const Duration(milliseconds: 300));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith('plank.png'),
      ),
      findsOneWidget,
    );

    for (var i = 0; i < 2; i++) {
      await t.tap(find.byKey(const ValueKey('tutorial_next')));
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text(S.t('tutorialRunTitle')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('tutorial_finish')));
    await _pumpBounded(t);
    expect(find.byKey(const ValueKey('tutorial_overlay')), findsNothing);
    expect(await (await ProgressStore.init()).tutorialSeen(), isTrue);

    await t.tap(find.byKey(const ValueKey('tutorial_help')));
    await t.pump();
    expect(find.byKey(const ValueKey('tutorial_overlay')), findsOneWidget);
    expect(find.text(S.t('tutorialGoalTitle')), findsOneWidget);
  });

  testWidgets('도움말의 첫 그림은 현재 스테이지 목표에 맞춰 바뀐다', (t) async {
    AppLang().value = 'ko';
    await _setSize(t, const Size(780, 360));
    await t.pumpWidget(
      MaterialApp(
        home: GameScreen(
          stageId: 'w1_s03',
          initialStage: _buttonStage('w1_s03'),
        ),
      ),
    );
    await _pumpBounded(t);

    await t.tap(find.byKey(const ValueKey('tutorial_help')));
    await t.pump();

    final assetNames = t
        .widgetList<Image>(find.byType(Image))
        .where((image) => image.image is AssetImage)
        .map((image) => (image.image as AssetImage).assetName)
        .toSet();
    expect(assetNames, contains('assets/images/parts/metal_ball.png'));
    expect(assetNames, contains('assets/images/parts/button.png'));
    expect(assetNames, isNot(contains('assets/images/parts/basket.png')));
  });

  test('StageLoader: 정상 JSON은 StageData로, 깨진 JSON은 StageLoadError로', () {
    const validJson =
        '{"id":"t","world":1,"index":1,'
        '"goal":{"type":"ball_in_basket"},"preset":[],'
        '"tray":[{"type":"plank","count":1}],'
        '"solution":[{"type":"plank","x":1,"y":1,"angle":0}]}';
    final parsed = StageLoader.parse('t', validJson);
    expect(parsed.id, 't');

    expect(
      () => StageLoader.parse('bad', '{not valid json'),
      throwsA(isA<StageLoadError>()),
    );
    expect(
      () => StageLoader.parse('bad', '{"id":"bad"}'),
      throwsA(isA<StageLoadError>()),
    );
  });

  testWidgets('클리어 콜백이 발생하면 progress에 기록되고, 다음 버튼을 누르면 다음 스테이지 화면으로 교체된다', (
    t,
  ) async {
    await _setSize(t, const Size(1600, 900));
    final progress = await ProgressStore.init();
    expect((await progress.cleared()).contains('w1_s01'), isFalse);

    final stageA = _trivialStage('w1_s01');
    await t.pumpWidget(
      MaterialApp(
        home: GameScreen(
          stageId: 'w1_s01',
          initialStage: stageA,
          loader: (id) async => _trivialStage(id),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }

    // GameWidget<T extends Game> is generic - find.byType does an exact
    // Type match, so the unparameterized `GameWidget` literal (which
    // instantiates to its bound, GameWidget<Game>) does NOT match a mounted
    // GameWidget<PiyakGame>. Name the concrete type argument instead.
    // `.game` is statically T? (nullable) because GameWidget.controlled
    // also shares this field and leaves it null - always non-null here
    // since GameScreen uses the plain GameWidget(game: ...) constructor.
    final game = t
        .widget<GameWidget<PiyakGame>>(find.byType(GameWidget<PiyakGame>))
        .game!;
    game.addPlacement(stageA.solution.single);
    await t.pump();

    await _tap(t, _runButtonCenter);
    await _pumpUntilCleared(t, game);
    expect(game.sim!.cleared, isTrue);

    expect(
      (await progress.cleared()).contains('w1_s01'),
      isTrue,
      reason: 'onCleared 시점에 markCleared가 호출되어야 함',
    );

    await _tap(t, WinOverlay.nextButtonCenter);
    await _pumpBounded(t);

    final next = t.widget<GameScreen>(find.byType(GameScreen));
    expect(next.stageId, 'w1_s02');
  });

  testWidgets('설정에서 언어를 한국어로 바꾸면 홈 화면 문구가 한국어로 바뀐다', (t) async {
    await _setSize(t, const Size(2000, 900));
    await t.pumpWidget(const PiyakScienceApp());
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.settings_rounded));
    await t.pumpAndSettle();

    await t.tap(find.text(S.t('langKo')));
    await t.pumpAndSettle();

    await t.pageBack();
    await t.pumpAndSettle();

    expect(AppLang().value, 'ko');
    expect(find.text(S.t('world1')), findsOneWidget);
  });

  // --- 추가 커버리지: lazy-load 설계의 성공/실패 분기 모두 실제로 동작함을 확인 ---

  testWidgets('해금된 스테이지 칸을 탭하면 게임 화면으로 전환된다', (t) async {
    await _setSize(t, const Size(1600, 900));
    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(stageLoader: (id) async => _trivialStage(id)),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('cell_w1_s01')));
    await _pumpBounded(t);

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);

    await t.tap(find.byIcon(Icons.home_rounded));
    await _pumpBounded(t);

    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('로드에 실패한 스테이지를 탭하면 화면 전환 없이 파손(⚠) 표시로 바뀐다', (t) async {
    await _setSize(t, const Size(2000, 900));
    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          stageLoader: (id) async => throw StageLoadError(id, 'broken'),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('cell_w1_s01')));
    await t.pumpAndSettle();

    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('⚠'), findsOneWidget);
  });

  testWidgets('마지막 스테이지를 클리어하고 다음을 누르면 홈 화면으로 돌아간다', (t) async {
    await _setSize(t, const Size(1600, 900));
    final lastId = stageOrder.last;
    // 마지막 스테이지만 빼고 전부 이미 클리어된 상태로 시작 - 마지막 칸이 바로 해금되게.
    SharedPreferences.setMockInitialValues({
      'cleared_v1': stageOrder.sublist(0, stageOrder.length - 1),
    });

    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(stageLoader: (id) async => _trivialStage(id)),
      ),
    );
    await t.pumpAndSettle();

    // 5 world cards don't all fit in the 1600-wide viewport this test needs
    // for the later fixed-resolution game tap math (_runButtonCenter) - drag
    // the horizontal world-card row so the last world's cell is on screen
    // before tapping it. The final stage (w5_s10) sits on world 5's FIRST
    // page (1-10), so no page switch is needed.
    await t.drag(find.byType(ListView), const Offset(-2400, 0));
    await t.pump();

    await t.tap(find.byKey(ValueKey('cell_$lastId')));
    await _pumpBounded(t);
    expect(find.byType(GameScreen), findsOneWidget);

    final game = t
        .widget<GameWidget<PiyakGame>>(find.byType(GameWidget<PiyakGame>))
        .game!;
    game.addPlacement(_trivialStage(lastId).solution.single);
    await t.pump();

    await _tap(t, _runButtonCenter);
    await _pumpUntilCleared(t, game);
    expect(game.sim!.cleared, isTrue);

    await _tap(t, WinOverlay.nextButtonCenter);
    await _pumpBounded(t);

    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}

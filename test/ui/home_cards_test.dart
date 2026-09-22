import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'pump_app.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/stage_data.dart';
import 'package:piyak_science/ui/game_screen.dart';
import 'package:piyak_science/ui/home_screen.dart';
import 'package:piyak_science/ui/strings.dart';
import 'package:piyak_science/ui/theme.dart';

/// nav_test.dart의 _trivialStage와 같은 모양 - 홈에서 셀을 탭해 게임 화면이
/// 뜨는지만 보면 되므로 아무 배치로나 클리어 가능한 최소 스테이지면 된다.
StageData _trivialStage(String id) => StageData.fromJson(
  jsonDecode(
        '{"id":"$id","world":5,"index":1,'
        '"goal":{"type":"ball_in_basket"},'
        '"preset":[{"type":"basket","x":8,"y":6,"angle":0}],'
        '"tray":[{"type":"rubber_ball","count":1}],'
        '"solution":[{"type":"rubber_ball","x":8,"y":2,"angle":0}]}',
      )
      as Map<String, dynamic>,
);

/// nav_test.dart의 '홈 화면에 월드 카드 5개가 렌더된다' 테스트와 동일한
/// 폭(2200) - 카드 5장(392폭+24마진=416*5=2080)이 스크롤 없이 한 화면에
/// 다 들어가야 find.text가 스크롤 없이도 전부 찾는다.
Future<void> _setSize(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    AppLang().value = 'system';
  });

  testWidgets('클리어한 스테이지 수만큼 월드 카드에 진행도 칩(n/20)이 표시된다', (t) async {
    SharedPreferences.setMockInitialValues({
      'cleared_v1': ['w1_s01', 'w1_s02', 'w1_s03'],
    });
    await _setSize(t, const Size(2200, 900));
    await pumpAppToHome(t);

    expect(find.text('3/20'), findsOneWidget); // world1: 3개 클리어
    expect(find.text('0/20'), findsNWidgets(4)); // world2~5: 0개
  });

  testWidgets('월드 카드 화살표로 11~20단계 페이지를 열 수 있다', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _setSize(t, const Size(2000, 900));
    await pumpAppToHome(t);

    expect(find.byKey(const ValueKey('cell_w1_s01')), findsOneWidget);
    expect(find.byKey(const ValueKey('cell_w1_s11')), findsNothing);

    await t.tap(find.byKey(const ValueKey('stage_page_next_w1')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('cell_w1_s01')), findsNothing);
    expect(find.byKey(const ValueKey('cell_w1_s11')), findsOneWidget);
    expect(find.text('11–20'), findsOneWidget);
  });

  testWidgets('짧은 가로형 휴대폰에서도 20단계 전환기가 넘치지 않는다', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _setSize(t, const Size(780, 360));
    await pumpAppToHome(t);

    await t.tap(find.byKey(const ValueKey('stage_page_next_w1')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('cell_w1_s20')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('월드5 첫 칸은 월드4를 다 깨기 전엔 잠겨 있고, 다 깨면 열려서 게임으로 진입한다', (t) async {
    // 1) 초기 상태: w5_s01 잠김 - 탭해도 화면 전환 없음.
    SharedPreferences.setMockInitialValues({});
    await _setSize(t, const Size(2200, 900));
    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(stageLoader: (id) async => _trivialStage(id)),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('cell_w5_s01')));
    await t.pump(const Duration(milliseconds: 350));
    expect(find.byType(GameScreen), findsNothing);

    // 2) 월드1~4를 전부 깬 상태: w5_s01이 열려 게임 화면으로 전환된다.
    // 같은 타입의 HomeScreen을 바로 다시 pump하면 기존 엘리먼트가 재사용돼
    // initState(진행도 재로딩)가 안 돌므로, 사이에 빈 트리를 한 번 끼운다.
    final w5Start = stageOrder.indexOf('w5_s01');
    SharedPreferences.setMockInitialValues({
      'cleared_v1': stageOrder.sublist(0, w5Start),
    });
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(stageLoader: (id) async => _trivialStage(id)),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('cell_w5_s01')));
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('배경 썸네일 로드가 실패하면 errorBuilder가 월드 고유색 컨테이너로 조용히 대체한다', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _setSize(t, const Size(2200, 900));
    await pumpAppToHome(t);

    // 월드 카드 5장 각자 헤더 썸네일(Image.asset) 하나씩 - 실제 asset
    // 로딩 성공/실패 타이밍(진짜 PNG 디코드라 runAsync 없인 test 안에서
    // 안 끝남)에 기대지 않고, errorBuilder 콜백 자체를 직접 호출해 그
    // 폴백 로직만 검증한다(명세의 "assert widget structure" 대안 경로).
    final images = t
        .widgetList<Image>(find.byType(Image))
        .where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.startsWith(
                'assets/images/bg/world',
              ),
        )
        .toList();
    expect(images.length, 5);

    final context = t.element(find.byType(Image).first);
    for (final image in images) {
      expect(image.errorBuilder, isNotNull);
      final fallback = image.errorBuilder!(
        context,
        Exception('no asset'),
        null,
      );
      expect(fallback, isA<Container>());
      final color = (fallback as Container).color;
      expect(
        worldCardColors.contains(color),
        isTrue,
        reason: '폴백 색은 항상 월드 고유 팔레트 중 하나여야 한다',
      );
    }
  });
}

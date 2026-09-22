import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/main.dart';

/// 앱을 띄운 뒤 메인 화면의 [시작하기]를 눌러 월드 목록까지 들어간다.
///
/// 앱의 첫 화면은 월드 목록이 아니라 메인 화면이다(title_screen.dart).
/// 월드 카드를 보는 테스트는 전부 이 한 걸음을 거쳐야 한다.
Future<void> pumpAppToHome(WidgetTester t) async {
  await t.pumpWidget(const PiyakScienceApp());
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('title_play')));
  await t.pumpAndSettle();
}

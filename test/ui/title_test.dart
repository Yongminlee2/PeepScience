import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/ui/home_screen.dart';
import 'package:piyak_science/ui/title_screen.dart';

void main() {
  // 메인 화면이 생기면서 월드 목록이 첫 화면이 아니게 됐다. 시작 버튼이
  // 월드 목록으로 이어지지 않으면 게임에 들어갈 방법이 아예 없어진다.
  testWidgets('시작 버튼을 누르면 월드 목록이 열린다', (t) async {
    await t.pumpWidget(const MaterialApp(home: TitleScreen()));
    expect(find.byType(HomeScreen), findsNothing);

    await t.tap(find.byKey(const ValueKey('title_play')));
    await t.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}

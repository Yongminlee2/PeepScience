import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/services/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 제목 일곱 번 = 개발자 모드(모든 판 열기). 여섯 번까지는 아무 일도 없어야
  // 아이가 우연히 켜지 않는다.
  testWidgets('제목을 일곱 번 두드리면 개발자 모드가 켜진다', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(const MaterialApp(home: TitleScreen()));
    await t.pumpAndSettle();
    final secret = find.byKey(const ValueKey('title_secret'));

    for (var i = 0; i < 6; i++) {
      await t.tap(secret);
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect((await ProgressStore.init()).devUnlockAll(), isFalse);

    await t.tap(secret);
    await t.pumpAndSettle();
    expect((await ProgressStore.init()).devUnlockAll(), isTrue);
  });
}

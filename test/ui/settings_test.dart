import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:piyak_science/ui/settings_screen.dart';
import 'package:piyak_science/ui/strings.dart';

Future<void> _setSize(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester t, Size size) async {
  await _setSize(t, size);
  await t.pumpWidget(const MaterialApp(home: SettingsScreen()));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLang().value = 'system';
  });

  testWidgets('언어 목록은 시스템 + 언어 표 전부가 자기 이름으로 렌더된다', (t) async {
    await _open(t, const Size(1600, 900));

    expect(
      find.byType(RadioListTile<String>),
      findsNWidgets(kLanguageOrder.length + 1),
    );
    expect(find.text(S.t('langSystem')), findsOneWidget);
    for (final code in kLanguageOrder) {
      expect(
        find.text(kLanguageNames[code]!),
        findsOneWidget,
        reason: '$code 항목이 자기 언어 이름으로 보이지 않는다',
      );
    }

    // dense로 줄여도 터치 타겟 최소치(48)는 지켜야 한다.
    expect(
      t.getSize(find.byKey(const ValueKey('lang_ko'))).height,
      greaterThanOrEqualTo(48.0),
    );
  });

  testWidgets('비영어 언어를 고르면 AppLang과 화면 문구가 즉시 바뀐다', (t) async {
    await _open(t, const Size(1600, 900));

    await t.tap(find.byKey(const ValueKey('lang_ja')));
    await t.pumpAndSettle();

    expect(AppLang().value, 'ja');
    // S.t는 이제 일본어를 돌려주므로, 그 문구가 화면에 있으면 즉시 반영된 것.
    expect(find.text(S.t('settings')), findsOneWidget);
    expect(find.text(S.t('language')), findsOneWidget);
  });

  testWidgets('세로 공간이 좁은 가로 화면에서도 마지막 언어까지 스크롤로 닿는다', (t) async {
    const height = 360.0;
    await _open(t, const Size(800, height));

    final last = find.byKey(ValueKey('lang_${kLanguageOrder.last}'));
    expect(
      t.getCenter(last).dy,
      greaterThan(height),
      reason: '한 화면에 다 들어오면 스크롤 검증이 의미가 없다',
    );

    await t.dragUntilVisible(
      last,
      find.byType(ListView),
      const Offset(0, -80),
    );
    await t.pumpAndSettle();
    expect(t.getCenter(last).dy, lessThan(height));

    await t.tap(last);
    await t.pumpAndSettle();
    expect(AppLang().value, kLanguageOrder.last);
  });
}

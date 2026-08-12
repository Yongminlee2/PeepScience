import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:piyak_science/main.dart';
import 'package:piyak_science/ui/strings.dart';

void main() {
  testWidgets('앱이 뜬다', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(const PiyakScienceApp());
    await t.pumpAndSettle();
    expect(find.text(S.t('appTitle')), findsOneWidget);
  });
}

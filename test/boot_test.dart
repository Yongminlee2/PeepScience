import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/main.dart';

void main() {
  testWidgets('앱이 뜬다', (t) async {
    await t.pumpWidget(const PiyakScienceApp());
    expect(find.text('Peep Science'), findsOneWidget);
  });
}

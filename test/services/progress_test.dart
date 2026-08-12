import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:piyak_science/services/progress.dart';
import 'package:piyak_science/sim/registry.dart';

void main() {
  group('ProgressStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initially only w1_s01 is unlocked', () async {
      final store = await ProgressStore.init();
      final cleared = await store.cleared();

      expect(store.isUnlocked('w1_s01', cleared), isTrue);
      expect(store.isUnlocked('w1_s02', cleared), isFalse);
      expect(store.isUnlocked('w1_s03', cleared), isFalse);
    });

    test('marking w1_s01 as cleared unlocks w1_s02', () async {
      final store = await ProgressStore.init();
      var cleared = await store.cleared();

      // Initially w1_s01 is unlocked but not cleared
      expect(store.isUnlocked('w1_s01', cleared), isTrue);
      expect(cleared.contains('w1_s01'), isFalse);

      // Mark w1_s01 as cleared
      await store.markCleared('w1_s01');

      // Now w1_s02 should be unlocked
      cleared = await store.cleared();
      expect(cleared.contains('w1_s01'), isTrue);
      expect(store.isUnlocked('w1_s02', cleared), isTrue);
      expect(store.isUnlocked('w1_s03', cleared), isFalse);
    });

    test('new ProgressStore instance sees persisted cleared list', () async {
      // First instance - mark w1_s01 as cleared
      var store = await ProgressStore.init();
      await store.markCleared('w1_s01');

      // Create new instance and verify persistence
      store = await ProgressStore.init();
      final cleared = await store.cleared();

      expect(cleared.contains('w1_s01'), isTrue);
      expect(store.isUnlocked('w1_s02', cleared), isTrue);
    });

    test('stageOrder has expected initial stages', () {
      expect(stageOrder.length, greaterThanOrEqualTo(3));
      expect(stageOrder[0], equals('w1_s01'));
      expect(stageOrder[1], equals('w1_s02'));
      expect(stageOrder[2], equals('w1_s03'));
    });
  });
}

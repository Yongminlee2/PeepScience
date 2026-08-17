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

    test('튜토리얼 완료 여부를 다음 실행에서도 기억한다', () async {
      var store = await ProgressStore.init();
      expect(await store.tutorialSeen(), isFalse);

      await store.markTutorialSeen();
      store = await ProgressStore.init();
      expect(await store.tutorialSeen(), isTrue);
    });

    test('stageOrder has expected initial stages', () {
      expect(stageOrder.length, greaterThanOrEqualTo(3));
      expect(stageOrder[0], equals('w1_s01'));
      expect(stageOrder[1], equals('w1_s02'));
      expect(stageOrder[2], equals('w1_s03'));
    });

    test('월드5 첫 판은 월드4 마지막 판을 깨야 열린다', () async {
      final store = await ProgressStore.init();

      // w4_s20 직전까지 전부 깨도 w5_s01은 잠김.
      final w5Start = stageOrder.indexOf('w5_s01');
      expect(w5Start, greaterThan(0));
      expect(stageOrder[w5Start - 1], 'w4_s20');
      final allButLast = stageOrder.sublist(0, w5Start - 1).toSet();
      expect(store.isUnlocked('w5_s01', allButLast), isFalse);

      // w4_s20까지 깨면 열린다 - 월드 체인이 5번째 월드로 이어진다.
      final throughW4 = stageOrder.sublist(0, w5Start).toSet();
      expect(store.isUnlocked('w5_s01', throughW4), isTrue);
      expect(store.isUnlocked('w5_s02', throughW4), isFalse);
    });

    test('별 기록은 최고 점수만 저장한다', () async {
      final store = await ProgressStore.init();
      await store.markStars('w1_s01', 2);
      await store.markStars('w1_s01', 1);
      expect((await store.stars())['w1_s01'], 2);

      await store.markStars('w1_s01', 3);
      final reopened = await ProgressStore.init();
      expect((await reopened.stars())['w1_s01'], 3);
    });

    test('기존 클리어 기록은 3성으로 보존한다', () async {
      SharedPreferences.setMockInitialValues({
        'cleared_v1': ['w1_s01'],
      });
      final store = await ProgressStore.init();
      expect(await store.stars(), {'w1_s01': 3});
    });

    test('신규 점수를 먼저 저장하면 레거시 보정이 덮어쓰지 않는다', () async {
      final store = await ProgressStore.init();
      await store.markStars('w1_s01', 2);
      await store.markCleared('w1_s01');
      expect(await store.stars(), {'w1_s01': 2});
    });

    test('깨진 별 저장값은 무시한다', () async {
      SharedPreferences.setMockInitialValues({
        'stars_v1': ['w1_s01:3', 'broken', 'w1_s02:9'],
      });
      final store = await ProgressStore.init();
      expect(await store.stars(), {'w1_s01': 3});
    });
  });
}

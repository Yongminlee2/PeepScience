import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/ui/strings.dart';

void main() {
  group('S.t - String lookup', () {
    test('returns translation for valid key', () {
      expect(S.t('appTitle'), isNotEmpty);
      expect(S.t('world1'), isNotEmpty);
      expect(S.t('clear'), isNotEmpty);
    });

    test('returns key itself for missing key', () {
      expect(S.t('nonExistentKey'), equals('nonExistentKey'));
    });

    test('every language carries exactly the English key set', () {
      final enKeys = S.strings['en']!.keys.toSet();
      for (final entry in S.strings.entries) {
        expect(
          entry.value.keys.toSet(),
          equals(enKeys),
          reason: '"${entry.key}" key set drifted from en',
        );
      }
    });

    test('no language has an empty value', () {
      for (final lang in S.strings.entries) {
        for (final entry in lang.value.entries) {
          expect(entry.value.trim(), isNotEmpty,
              reason: '${lang.key}/${entry.key} is empty');
        }
      }
    });

    test('every language keeps the {n} placeholder in stageN', () {
      for (final entry in S.strings.entries) {
        expect(entry.value['stageN'], contains('{n}'),
            reason: '${entry.key}/stageN lost its {n} placeholder');
      }
    });

    test('kLanguageOrder and kLanguageNames cover every table', () {
      expect(kLanguageOrder.toSet(), equals(kStrings.keys.toSet()));
      expect(kLanguageOrder.length, equals(kStrings.length),
          reason: 'kLanguageOrder has a duplicate');
      expect(kLanguageNames.keys.toSet(), equals(kStrings.keys.toSet()));
    });

    test('ko values contain Hangul characters', () {
      final koStrings = S.strings['ko']!;
      for (final entry in koStrings.entries) {
        // Check if value contains at least one Hangul character
        // Hangul range: U+AC00 to U+D7A3
        final hasHangul = entry.value.runes.any((rune) =>
            (rune >= 0xAC00 && rune <= 0xD7A3) || // Hangul Syllables
            (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
            (rune >= 0x3130 && rune <= 0x318F)); // Hangul Compatibility Jamo
        expect(hasHangul, isTrue,
            reason: 'Ko value for key "${entry.key}" should contain Hangul');
      }
    });

    test('en values do not contain Hangul characters', () {
      final enStrings = S.strings['en']!;
      for (final entry in enStrings.entries) {
        // Check that value does NOT contain Hangul characters
        final hasHangul = entry.value.runes.any((rune) =>
            (rune >= 0xAC00 && rune <= 0xD7A3) || // Hangul Syllables
            (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
            (rune >= 0x3130 && rune <= 0x318F)); // Hangul Compatibility Jamo
        expect(hasHangul, isFalse,
            reason: 'En value for key "${entry.key}" should not contain Hangul');
      }
    });
  });

  group('S.codeForLocale - device locale to table', () {
    test('Chinese splits on script, then on country', () {
      expect(S.codeForLocale('zh', 'Hant', null), 'zh_Hant');
      expect(S.codeForLocale('zh', null, 'TW'), 'zh_Hant');
      expect(S.codeForLocale('zh', null, 'CN'), 'zh');
    });

    test('a language we do not carry resolves to null', () {
      expect(S.codeForLocale('xx', null, null), isNull);
    });
  });

  group('AppLang - Language preference', () {
    test('AppLang initializes with "system"', () {
      final lang = AppLang();
      expect(lang.value, equals('system'));
    });

    test('AppLang can be set to "ko" or "en"', () {
      final lang = AppLang();
      lang.value = 'ko';
      expect(lang.value, equals('ko'));
      lang.value = 'en';
      expect(lang.value, equals('en'));
    });
  });

  group('All required string keys', () {
    test('contains all required keys from brief', () {
      final requiredKeys = [
        'appTitle',
        'world1',
        'world2',
        'world3',
        'world4',
        'world5',
        'clear',
        'next',
        'retry',
        'settings',
        'sound',
        'language',
        'langSystem',
        'goalBasket',
        'goalButton',
        'goalBalloons',
        'goalDominoes',
      ];

      final enKeys = S.strings['en']!.keys.toSet();
      for (final key in requiredKeys) {
        expect(enKeys.contains(key), isTrue,
            reason: 'Missing required key: $key');
      }
    });
  });
}

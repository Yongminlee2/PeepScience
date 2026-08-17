import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/l10n.dart';

export 'l10n/l10n.dart' show kLanguageNames, kLanguageOrder, kStrings;

/// String lookup for the current [AppLang] choice.
class S {
  /// Language tables, keyed by language code. Kept as a member so callers
  /// (and tests) can inspect coverage without importing the l10n folder.
  static const Map<String, Map<String, String>> strings = kStrings;

  /// Language used when the device asks for one we do not carry, and to
  /// backfill any key a translation is missing.
  static const String fallback = 'en';

  /// Translate a key using the current [AppLang] setting.
  ///
  /// A missing key returns the key itself rather than throwing — an
  /// untranslated string is a visible bug on screen, not a crash (and
  /// `strings_test.dart` catches it before that).
  static String t(String key) {
    final lang = _resolveLanguage(AppLang().value);
    return strings[lang]?[key] ?? strings[fallback]![key] ?? key;
  }

  /// Human-friendly stage label ("Backyard · Stage 7"). The number lives in
  /// a `{n}` placeholder so languages that put it before the word (or use a
  /// counter word, as Korean does) stay natural.
  static String stageLabel(int world, int index) =>
      '${t('world$world')} · ${t('stageN').replaceAll('{n}', '$index')}';

  /// Resolve a stored preference to a language table.
  /// 'system' is resolved against the platform locale at lookup time, so a
  /// device language change lands without an app restart.
  static String _resolveLanguage(String lang) {
    if (strings.containsKey(lang)) return lang;
    for (final locale in PlatformDispatcher.instance.locales) {
      final code = codeForLocale(
        locale.languageCode,
        locale.scriptCode,
        locale.countryCode,
      );
      if (code != null) return code;
    }
    return fallback;
  }

  /// Device locale → one of our tables, or null when we carry nothing for it.
  ///
  /// Chinese is the only language with two tables. Taiwan, Hong Kong and
  /// Macao read traditional characters; showing them simplified is legible
  /// but reads as another country's writing. Android reports this as
  /// `zh-Hant` sometimes and as a bare `zh-TW` other times, so both are
  /// checked.
  static String? codeForLocale(String lang, String? script, String? country) {
    if (lang == 'zh') {
      final traditional =
          script == 'Hant' ||
          const {'TW', 'HK', 'MO'}.contains(country?.toUpperCase());
      return traditional ? 'zh_Hant' : 'zh';
    }
    return strings.containsKey(lang) ? lang : null;
  }
}

/// Application language preference, persisted via shared_preferences.
/// Values: 'system' or any key of [kStrings].
class AppLang extends ValueNotifier<String> {
  static final AppLang _instance = AppLang._();

  AppLang._() : super('system') {
    _init();
  }

  factory AppLang() {
    return _instance;
  }

  /// Initialize from shared_preferences.
  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('lang');
      if (stored != null && isSupported(stored)) {
        value = stored;
      }
    } catch (e) {
      // If prefs fails, stay with default 'system'
    }
  }

  /// Whether a stored/selected value is one this build can honour. Guards
  /// against a preference left behind by a build that carried more
  /// languages than this one.
  static bool isSupported(String lang) =>
      lang == 'system' || kStrings.containsKey(lang);

  /// Override value setter to persist to shared_preferences.
  @override
  set value(String newValue) {
    super.value = newValue;
    _persistLang(newValue);
  }

  /// Persist language preference to shared_preferences.
  Future<void> _persistLang(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lang', lang);
    } catch (e) {
      // Silently ignore if persistence fails
    }
  }
}

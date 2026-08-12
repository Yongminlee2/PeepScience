import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// String localization class - provides en/ko translation lookup.
class S {
  static final Map<String, Map<String, String>> strings = {
    'en': {
      'appTitle': 'Peep Science',
      'world1': 'Bedroom',
      'world2': 'Backyard',
      'world3': 'Toy Factory',
      'world4': 'Space',
      'clear': 'CLEAR!',
      'next': 'Next',
      'retry': 'Retry',
      'settings': 'Settings',
      'sound': 'Sound',
      'language': 'Language',
      'langSystem': 'System',
      'goalBasket': 'Ball into the basket!',
      'goalButton': 'Press the button!',
      'goalBalloons': 'Pop all balloons!',
      'goalDominoes': 'Topple all dominoes!',
    },
    'ko': {
      'appTitle': '삐약과학',
      'world1': '아이 방',
      'world2': '뒷마당',
      'world3': '장난감 공장',
      'world4': '우주',
      'clear': '클리어!',
      'next': '다음',
      'retry': '다시',
      'settings': '설정',
      'sound': '소리',
      'language': '언어',
      'langSystem': '기기 설정',
      'goalBasket': '공을 바구니에!',
      'goalButton': '버튼을 눌러라!',
      'goalBalloons': '풍선을 모두 터뜨려라!',
      'goalDominoes': '도미노를 모두 쓰러뜨려라!',
    },
  };

  /// Translate a key using current AppLang setting.
  /// Returns the key itself if not found (never crashes).
  static String t(String key) {
    final lang = AppLang().value;
    final targetLang = _resolveLanguage(lang);
    final translation = strings[targetLang]?[key];
    return translation ?? key;
  }

  /// Resolve language code to actual language (en or ko).
  /// 'system' resolves via platform locale at lookup time.
  static String _resolveLanguage(String lang) {
    if (lang == 'system') {
      // Resolve from platform locale
      final locale = PlatformDispatcher.instance.locale;
      if (locale.languageCode == 'ko') {
        return 'ko';
      }
      return 'en';
    }
    return lang == 'ko' ? 'ko' : 'en';
  }
}

/// Application language preference, persisted via shared_preferences.
/// Values: 'system', 'ko', 'en'
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
      if (stored != null && (stored == 'system' || stored == 'ko' || stored == 'en')) {
        value = stored;
      }
    } catch (e) {
      // If prefs fails, stay with default 'system'
    }
  }

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

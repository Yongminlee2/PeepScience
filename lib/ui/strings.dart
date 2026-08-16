import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// String localization class - provides en/ko translation lookup.
class S {
  static final Map<String, Map<String, String>> strings = {
    'en': {
      'appTitle': 'Peep Science',
      'homeTagline': 'Build · Test · Discover',
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
      'langKo': 'Korean',
      'langEn': 'English',
      'goalBasket': 'Ball into the basket!',
      'goalButton': 'Press the button!',
      'goalBalloons': 'Pop all balloons!',
      'goalDominoes': 'Topple all dominoes!',
      'dragHint': 'Drag a part in, turn the yellow handle, then press play.',
      'clearMessage': 'Your contraption came to life!',
      'scienceNote': 'OBSERVE',
      'factBasket': 'Slopes and rebounds change the path of a moving ball.',
      'factButton': 'A force can move an object or press it down.',
      'factBalloons': 'Light balloons react strongly to air forces.',
      'factDominoes': 'Motion can transfer from one object to the next.',
      'home': 'Home',
      'playStage': 'Play stage',
      'predictionQuestion': 'Which ball will work better?',
      'predictionHint': 'Choose first, then run the experiment!',
      'predictionCorrect': 'Prediction matched the result!',
      'predictionWrong': 'A surprise result — try the other material!',
      'chainReaction': 'CHAIN REACTION',
      'challengeTitle': 'STAR CHALLENGE',
      'partLimit': 'Use no more than',
      'starsEarned': 'Stars earned',
      'tutorialHelp': 'Experiment guide',
      'tutorialTitle': "Peep Professor's Lab Notes",
      'tutorialSubtitle': 'Four tiny steps, then you are the scientist!',
      'tutorialGoalTitle': '1. Check the mission card',
      'tutorialGoalBody':
          'Each stage has a different goal. Tap the mission card to make the basket, button, balloon, or domino bounce and wave.',
      'tutorialDragTitle': '2. Drag in a part',
      'tutorialDragBody':
          'Pull a part up from the tray and drop it in an empty space. A yellow guide means the spot is ready.',
      'tutorialRotateTitle': '3. Turn the yellow handle',
      'tutorialRotateBody':
          'Tap your plank, then drag its yellow handle to build a path for the ball.',
      'tutorialRunTitle': '4. Run and observe',
      'tutorialRunBody':
          'Press the green play button. A miss is useful too: your parts stay put, so adjust them and test again!',
      'tutorialSkip': 'Skip for now',
      'tutorialBack': 'Back',
      'tutorialNext': 'Next',
      'tutorialStart': 'Start experiment',
    },
    'ko': {
      'appTitle': '삐약과학',
      'homeTagline': '만들고 · 실험하고 · 발견해요',
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
      'langKo': '한국어',
      'langEn': '영어',
      'goalBasket': '공을 바구니에!',
      'goalButton': '버튼을 눌러라!',
      'goalBalloons': '풍선을 모두 터뜨려라!',
      'goalDominoes': '도미노를 모두 쓰러뜨려라!',
      'dragHint': '부품을 끌어 놓고 노란 손잡이로 돌린 뒤 ▶를 눌러 보세요.',
      'clearMessage': '멋진 장치가 움직였어요!',
      'scienceNote': '관찰해 봐요',
      'factBasket': '경사와 반발을 바꾸면 움직이는 공의 길이 달라져요.',
      'factButton': '힘은 물체를 움직이거나 아래로 누를 수 있어요.',
      'factBalloons': '가벼운 풍선은 공기의 힘에 더 크게 움직여요.',
      'factDominoes': '한 물체의 움직임은 다음 물체로 전달될 수 있어요.',
      'home': '홈으로',
      'playStage': '스테이지 시작',
      'predictionQuestion': '어느 공이 더 잘 움직일까?',
      'predictionHint': '먼저 고르고 실험해 봐요!',
      'predictionCorrect': '예측과 결과가 같았어요!',
      'predictionWrong': '뜻밖의 결과예요. 다른 재료도 해봐요!',
      'chainReaction': '연쇄 반응!',
      'challengeTitle': '별 도전',
      'partLimit': '부품 수 제한',
      'starsEarned': '이번에 모은 별',
      'tutorialHelp': '실험 안내 보기',
      'tutorialTitle': '삐약 박사의 실험 수첩',
      'tutorialSubtitle': '네 가지만 알면 이제 나도 꼬마 과학자!',
      'tutorialGoalTitle': '1. 미션 카드를 확인해요',
      'tutorialGoalBody':
          '스테이지마다 목표가 달라요. 미션 카드를 누르면 바구니·버튼·풍선·도미노 중 목표물이 콩콩 움직여요.',
      'tutorialDragTitle': '2. 부품을 끌어 놓아요',
      'tutorialDragBody': '아래 부품을 손가락으로 끌어 빈 곳에 놓아요. 노란 안내선이 보이면 놓을 수 있어요.',
      'tutorialRotateTitle': '3. 노란 손잡이로 돌려요',
      'tutorialRotateBody': '놓은 판자를 누른 뒤 노란 손잡이를 빙글 돌려 공이 갈 길을 만들어요.',
      'tutorialRunTitle': '4. 실행하고 관찰해요',
      'tutorialRunBody': '초록 ▶를 누르면 실험 시작! 실패해도 부품은 그대로니까 고쳐서 다시 해봐요.',
      'tutorialSkip': '지금은 건너뛰기',
      'tutorialBack': '이전',
      'tutorialNext': '다음',
      'tutorialStart': '첫 실험 시작',
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

  /// Human-friendly stage label, localized without putting format syntax in
  /// the asset-less string table.
  static String stageLabel(int world, int index) {
    final lang = _resolveLanguage(AppLang().value);
    final worldName = t('world$world');
    return lang == 'ko' ? '$worldName · $index단계' : '$worldName · Stage $index';
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
      if (stored != null &&
          (stored == 'system' || stored == 'ko' || stored == 'en')) {
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

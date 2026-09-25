import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 광고는 전면 광고 하나만 쓴다. 뜨는 때는 두 번뿐이다.
///  * 앱을 켜고 처음 스테이지를 열 때 한 번
///  * 그 뒤로 스테이지를 [_stagesPerAd]판 넘길 때마다 한 번
///
/// 띠(배너) 광고는 쓰지 않는다. 게임 화면에 붙이면 판이 12~14% 작아지고,
/// 메인·월드 목록에 붙이는 것은 이 게임에 비해 과하다고 판단해 뺐다.
///
/// 광고는 어디까지나 부가 기능이다. 초기화·로드·표시가 모두 실패해도
/// 게임은 평소처럼 돌아가야 하므로, 이 파일 안에서 모든 예외를 삼킨다.
class Ads {
  Ads._();

  /// 애드몹 콘솔에서 만든 실제 광고 단위 ID.
  /// 디버그 빌드는 항상 구글 테스트 ID를 쓰므로, 개발 중 광고를 눌러도
  /// 계정이 무효 트래픽으로 걸리지 않는다.
  static const _realInterstitialAndroid =
      'ca-app-pub-6583185616347720/4585125107';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';

  /// 몇 판마다 한 번 띄울지. 3판은 흔한 캐주얼 퍼즐 간격이고, 1~2판으로
  /// 줄이면 아이가 못 참는다.
  static const _stagesPerAd = 3;

  static bool _ready = false;
  static final Completer<void> _initDone = Completer<void>();

  static void _markInitDone() {
    if (!_initDone.isCompleted) _initDone.complete();
  }

  static bool _initStarted = false;
  static bool _sessionAdShown = false;
  static int _advances = 0;
  static InterstitialAd? _ad;
  static bool _loading = false;

  static String get _interstitialUnitId =>
      kReleaseMode ? _realInterstitialAndroid : _testInterstitialAndroid;

  /// 실제 ID를 아직 안 넣은 채로 정식 빌드를 올리는 사고를 막는다. 그런
  /// 빌드는 광고를 아예 요청하지 않으므로, 잘못된 ID로 구글에 요청을 보내는
  /// 일도 테스트 광고가 이용자에게 보이는 일도 없다.
  static bool get _configured =>
      !kReleaseMode || !_realInterstitialAndroid.contains('pub-0000');

  /// 앱 시작 때 한 번. 광고 SDK를 깨우고, 유럽 이용자 동의 창이 필요하면
  /// 먼저 띄운 뒤 첫 광고를 미리 받아 둔다.
  static Future<void> init() async {
    if (!_configured) return;
    _initStarted = true;
    try {
      await MobileAds.instance.initialize();
      // 그림체가 유아 친화적이라 전체이용가 등급 광고만 받는다.
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
      );
      await _requestConsent();
      _ready = true;
      unawaited(_load());
    } catch (_) {
      // 광고 없이 그냥 게임만 돌아간다.
    } finally {
      _markInitDone();
    }
  }

  /// 유럽·영국 이용자에게는 동의를 받아야 광고를 띄울 수 있다(구글 EU 이용자
  /// 동의 정책). 그 밖의 지역에서는 요청만 하고 창이 뜨지 않는다.
  /// 응답이 없어도 게임 시작을 막지 않도록 8초에서 끊는다.
  static Future<void> _requestConsent() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        } catch (_) {
          // 동의 창을 못 띄우면 개인 맞춤이 아닌 광고로 넘어간다.
        }
        if (!done.isCompleted) done.complete();
      },
      (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  static Future<void> _load() async {
    if (_loading || _ad != null) return;
    _loading = true;
    try {
      await InterstitialAd.load(
        adUnitId: _interstitialUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _loading = false;
          },
          onAdFailedToLoad: (_) {
            _loading = false;
          },
        ),
      );
    } catch (_) {
      _loading = false;
    }
  }

  /// 앱을 켜고 처음 스테이지를 열 때 한 번 띄운다. 첫 광고가 아직 안
  /// 받아졌으면 이번엔 건너뛴다 - 광고를 기다리느라 판이 늦게 열리면 안 된다.
  /// 초기화(동의 창 포함)가 끝나지 않았으면 잠깐 기다린다.
  static Future<void> maybeShowOnSessionStart() async {
    // init()을 안 부른 곳(테스트·광고 없는 빌드)은 기다릴 것도 없다.
    if (_sessionAdShown || !_initStarted) return;
    await _initDone.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    if (!_ready || _sessionAdShown) return;
    _sessionAdShown = true;
    await _show();
  }

  /// 다음 판으로 넘어갈 때 호출한다. 차례가 아니거나 받아 둔 광고가 없으면
  /// 아무 일도 없이 바로 돌아간다 - 광고 때문에 다음 판이 늦게 열리면 안 된다.
  static Future<void> maybeShowOnStageAdvance() async {
    if (!_ready) return;
    _advances++;
    if (_advances % _stagesPerAd != 0) return;
    await _show();
  }

  static Future<void> _show() async {
    final ad = _ad;
    if (ad == null) {
      unawaited(_load());
      return;
    }
    _ad = null;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(_load());
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        unawaited(_load());
        if (!closed.isCompleted) closed.complete();
      },
    );
    try {
      await ad.show();
      await closed.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );
    } catch (_) {
      // 표시에 실패하면 그냥 넘어간다.
    }
  }

  /// 테스트에서 광고 경로를 건드리지 않았는지 확인할 때 쓴다.
  @visibleForTesting
  static int get advances => _advances;
}

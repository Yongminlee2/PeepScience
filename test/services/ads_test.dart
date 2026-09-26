import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/services/ads.dart';

void main() {
  // 광고 SDK가 없는 곳(테스트·초기화 실패·기내 모드)에서 판을 넘길 때마다
  // 플러그인을 건드리면 게임 진행이 멈춘다. 초기화 전에는 아무 일도 하지
  // 않고 즉시 돌아와야 한다.
  test('초기화 전에는 판을 넘겨도 광고 경로를 건드리지 않는다', () async {
    await Ads.maybeShowPending().timeout(const Duration(seconds: 1));
    await Ads.maybeShowPending().timeout(const Duration(seconds: 1));
  });

  // 월드 목록에서 판을 열 때마다 불린다. 광고 SDK를 안 깨운 곳에서 여기서
  // 기다리면 판이 영영 안 열린다.
  test('초기화 전에는 게임 시작 광고도 기다리지 않고 바로 돌아온다', () async {
    await Ads.maybeShowOnSessionStart().timeout(
      const Duration(milliseconds: 100),
    );
  });

  // 깨고 [다음] 대신 홈으로 나가도 깬 판은 세야 한다(전에는 [다음]만 셌다).
  test('깬 판 수는 나가는 길과 상관없이 쌓인다', () {
    final before = Ads.clearsSinceAd;
    Ads.onStageCleared();
    Ads.onStageCleared();
    expect(Ads.clearsSinceAd, before + 2);
  });
}

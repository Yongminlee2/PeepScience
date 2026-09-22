import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/services/ads.dart';

void main() {
  // 광고 SDK가 없는 곳(테스트·초기화 실패·기내 모드)에서 판을 넘길 때마다
  // 플러그인을 건드리면 게임 진행이 멈춘다. 초기화 전에는 아무 일도 하지
  // 않고 즉시 돌아와야 한다.
  test('초기화 전에는 판을 넘겨도 광고 경로를 건드리지 않는다', () async {
    await Ads.maybeShowOnStageAdvance().timeout(const Duration(seconds: 1));
    await Ads.maybeShowOnStageAdvance().timeout(const Duration(seconds: 1));
    expect(Ads.advances, 0);
  });
}

// Sound 서비스 검증. audioplayers의 네이티브 채널은 flutter test 환경에
// 등록돼 있지 않으므로(플러그인 목이 없음) 실제 재생 시도는 항상 내부에서
// 실패한다 - 이는 오히려 "실패를 삼키는지"를 실제 코드 경로 그대로 검증하는
// 좋은 조건이다(가짜로 흉내낼 필요가 없다).
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/services/sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Sound.setEnabled(true);
    Sound.debugPlayAttempts = 0;
  });

  test('init()은 (플러그인 미등록 = 에셋/재생 전부 실패하는) 환경에서도 예외를 던지지 않는다', () async {
    await Sound.init(); // 던지면 이 테스트 자체가 실패한다.
  });

  test('init()을 두 번 불러도 예외를 던지지 않는다(풀 재생성 경로)', () async {
    await Sound.init();
    await Sound.init(); // 쓰던 풀을 dispose하고 다시 만드는 경로도 안전해야 한다.
  });

  test('setEnabled(false)면 play()가 재생을 시도조차 하지 않는다(no-op)', () async {
    Sound.setEnabled(false);
    await Sound.play(Sfx.tap);
    expect(Sound.debugPlayAttempts, 0);
  });

  test('setEnabled(true)면 play()가 재생을 시도한다(성공 여부와 무관)', () async {
    Sound.setEnabled(true);
    await Sound.play(Sfx.tap);
    expect(Sound.debugPlayAttempts, 1);
  });

  test('꺼짐 -> 켬으로 바뀌면 그 다음부터 다시 시도한다', () async {
    Sound.setEnabled(false);
    await Sound.play(Sfx.win);
    expect(Sound.debugPlayAttempts, 0);

    Sound.setEnabled(true);
    await Sound.play(Sfx.win);
    expect(Sound.debugPlayAttempts, 1);
  });

  test('풀이 없어도(초기화 전) play()는 예외를 던지지 않는다', () async {
    // init()을 부르지 않은 상태 그대로 - _pools가 비어 있을 때의 폴백.
    await Sound.play(Sfx.pop);
    expect(Sound.debugPlayAttempts, 1);
  });
}

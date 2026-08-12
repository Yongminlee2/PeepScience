import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// 효과음 종류. 파일명은 'audio/${Sfx.name}.wav'(tool/gen_sfx.dart가 만들고
/// assets/audio/에 커밋된 것) - 이름이 어긋나도 재생만 조용히 안 될 뿐 앱은
/// 죽지 않는다([Sound.play]의 무음 폴백).
enum Sfx { tap, place, pop, boing, win, gearTick, buttonClick }

/// 합성 효과음 재생 + (있으면) BGM 루프. 정적 메서드만 있는 네임스페이스.
///
/// 실패는 전부 삼켜 무음으로 물러난다 - 오디오 하나 때문에 게임이 멈추거나
/// 죽으면 안 된다. 삐약푸시에서 실제로 앱이 통째로 죽은 사고가 있었다:
/// 재생 실패 후 되살리며 쓰던 풀을 반납하지 않아 네이티브 플레이어가 계속
/// 쌓였던 것이 원인이었다. 그 교훈 두 가지를 그대로 지킨다.
///  ① 풀을 새로 만들면(=[init]을 다시 호출하면) 쓰던 풀을 반드시 dispose.
///  ② 초기화·재생 실패는 try-catch로 삼켜 무음 진행.
///
/// ponytail: 삐약푸시의 SoundService는 재생 실패 시 풀을 최대 3번까지
/// 되살리는 로직이 있다(걸음마다 소리 내는 게임이라 필요했다). 여기는
/// 트리거가 훨씬 드물어(배치·삭제·클리어 등 이산적 이벤트 + 0.5초
/// 스로틀된 gearTick) 되살리기 없이 "이번 재생은 실패, 다음 재생은 다시
/// 시도"만으로 충분하다고 보고 생략했다 - 풀 하나가 영구히 죽으면 그
/// 소리만 계속 안 나는 게 한계; 필요해지면 삐약푸시의 revive 패턴을
/// 옮겨온다.
class Sound {
  Sound._();

  static bool _enabled = true;
  static final Map<Sfx, AudioPool> _pools = {};
  static AudioPlayer? _bgmPlayer;
  static const double _kBgmVolume = 0.3;

  /// 테스트 확인용 - enabled 게이트를 통과해 실제 재생을 시도한 횟수(성공
  /// 여부는 안 셈). 모의 프레임워크 없이 no-op을 확인하기 위한 최소 관찰창.
  @visibleForTesting
  static int debugPlayAttempts = 0;

  static void setEnabled(bool v) {
    _enabled = v;
    final bgm = _bgmPlayer;
    if (bgm == null) return;
    unawaited((v ? bgm.resume() : bgm.pause()).catchError((_) {}));
  }

  /// 앱 시작 시 한 번(main.dart, non-blocking으로 호출) - 효과음 7종 풀을
  /// 선로드하고 BGM(파일 있으면)을 시작한다. 실패는 소리 단위로 삼킨다:
  /// 하나가 없거나 깨져도 나머지 로딩을 막지 않는다. 두 번째 호출부터는
  /// 쓰던 풀을 먼저 dispose하고 다시 만든다(iron rule ①).
  static Future<void> init() async {
    for (final old in _pools.values) {
      try {
        await old.dispose();
      } catch (_) {
        // 반납 실패는 무시 - 그래도 새로 만드는 건 계속 진행한다.
      }
    }
    _pools.clear();
    // BGM도 같은 규칙 - 쓰던 플레이어를 반드시 반납하고서 새로 만든다
    // (오늘은 bgm 파일이 없어 이 경로가 실제로 안 타지만, 나중에 파일이
    // 생겼을 때 init()이 두 번 불리면 그대로 새는 자리라 미리 막아 둔다).
    final oldBgm = _bgmPlayer;
    _bgmPlayer = null;
    if (oldBgm != null) {
      try {
        await oldBgm.dispose();
      } catch (_) {
        // 반납 실패는 무시.
      }
    }

    Set<String> manifest;
    try {
      manifest = await AssetManifest.loadFromAssetBundle(rootBundle)
          .then((m) => m.listAssets().toSet());
    } catch (_) {
      manifest = const <String>{}; // 매니페스트조차 못 읽으면 전부 무음.
    }

    for (final s in Sfx.values) {
      final path = 'audio/${s.name}.wav';
      if (!manifest.contains('assets/$path')) continue;
      try {
        _pools[s] =
            await AudioPool.createFromAsset(path: path, maxPlayers: 2);
      } catch (_) {
        // 이 소리만 포기 - 나머지는 계속 로드한다.
      }
    }
    await _initBgm(manifest);
  }

  /// bgm.mp3 또는 bgm.ogg가 번들에 있으면 낮은 볼륨으로 루프 재생 - 오늘은
  /// 아무 파일도 커밋돼 있지 않으니 배선만 해 두고 항상 무음으로 남는다.
  static Future<void> _initBgm(Set<String> manifest) async {
    for (final ext in ['mp3', 'ogg']) {
      final path = 'audio/bgm.$ext';
      if (!manifest.contains('assets/$path')) continue;
      try {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(AssetSource(path), volume: _kBgmVolume);
        if (!_enabled) await player.pause();
        _bgmPlayer = player;
      } catch (_) {
        // BGM 실패는 무음으로 - 효과음엔 영향 없음.
      }
      return;
    }
  }

  /// 효과음 하나 재생. 꺼져 있으면 아무 것도 하지 않는다(no-op) - 풀이
  /// 없거나(파일 없음/[init] 전) 재생 자체가 실패해도 예외를 밖으로 던지지
  /// 않는다.
  static Future<void> play(Sfx s) async {
    if (!_enabled) return;
    debugPlayAttempts++;
    try {
      await _pools[s]?.start();
    } catch (_) {
      // 소리 하나 실패했다고 게임이 멈추면 안 된다.
    }
  }
}

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/part_view.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';

import '../sim/helpers.dart';

// 이미지 에셋 14종(부품 12 + 목표물 2) 전체의 json id. platform은 발주서
// 14종엔 없음 - 일부러 빠져 있다(타일 스프라이트는 따로 있음 - art-request.md
// 계약 밖의 손맛 패스, part_view.dart의 _spriteRelPath doc 참고).
final _ids = [...PartType.values.map(jsonIdOf), 'basket', 'button'];

void main() {
  testWidgets('실제 에셋 번들에서는 14종 스프라이트가 전부 로드된다', (t) async {
    final preset = [
      for (var i = 0; i < _ids.length; i++)
        '{"type":"${_ids[i]}","x":${i + 1},"y":1,"angle":0}'
    ].join(',');
    final s = stage(preset, '', '{"type":"plank","x":0,"y":0,"angle":0}');

    final game = PiyakGame(s);
    await t.pumpWidget(GameWidget(game: game));
    // PartView.onLoad가 이제 실제 PNG를 디코딩한다(Sprite.load, 14개 전부
    // 실물 에셋이 있으므로). dart:ui의 이미지 디코드는 진짜 비동기 콜백이라
    // flutter test의 FakeAsync 안에서는 t.pump()만 아무리 반복해도(40회까지
    // 직접 확인) 절대 안 끝난다 - AssetManifest 조회(순수 Dart future)만
    // 필요했던 이전 세대 테스트(placement_test.dart 등)와 달리, runAsync로
    // 진짜 이벤트 루프를 한 번 돌려 디코드를 실제로 끝내야 한다. 그 다음
    // 컴포넌트 트리에 반영하려면 pump가 최소 1번 더 필요 - 아래는 기존
    // 관례(~10 pump)를 그대로 유지해 여유를 둔다.
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }

    // 27장 적용 후 상태: 매니페스트에 14종 스프라이트 경로가 전부 있어야 한다.
    final manifest = await loadAssetManifestPaths();
    for (final id in _ids) {
      expect(manifest.contains('assets/images/parts/$id.png'), isTrue,
          reason: '$id.png가 번들에 있어야 한다');
    }

    // 실제로 뜬 PartView 14개 전부 스프라이트를 로드해서 도형 폴백을 쓰지
    // 않아야 한다.
    final views = game.world.children.whereType<PartView>().toList();
    expect(views.length, _ids.length);
    for (final v in views) {
      expect(v.hasSprite, isTrue);
    }
  });

  testWidgets(
      'platform은 이제 타일 스프라이트를 로드해 렌더되고(크래시 없음), 없는 에셋 경로는 매니페스트 게이트가 막는다',
      (t) async {
    // platform_tile.png(256x128, seamless)가 번들에 추가되면서 part_view.dart
    // _spriteRelPath의 'parts/platform_tile.png' 경로가 이제 manifest.contains
    // 체크를 통과해 onLoad가 실제 PNG를 디코드한다(Sprite.load) - Test A와
    // 같은 이유로 runAsync + 실제 딜레이가 필요하다: dart:ui의 이미지 디코드는
    // 진짜 비동기 콜백이라 FakeAsync 안에서는 pump()만 반복해선 절대 안 끝나고
    // (그러는 동안 이 PartView는 로딩 중 상태라 world.children에도 안 잡힌다 -
    // runAsync 없이 돌려서 확인함: views.length가 0으로 나온다), 트리에
    // 반영되려면 그 후 pump가 최소 1번 더 필요하다.
    final s = stage('{"type":"platform","x":8,"y":8,"angle":0,"w":4}', '',
        '{"type":"plank","x":0,"y":0,"angle":0}');

    final game = PiyakGame(s);
    await t.pumpWidget(GameWidget(game: game));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }

    // platform 프리셋이 실제로 타일 스프라이트를 로드하고, render()의
    // _renderPlatformTile 경로가 크래시 없이 돈다 - 이 프로젝트 최초의
    // 타일 스프라이트 커버리지.
    final views = game.world.children.whereType<PartView>().toList();
    expect(views.length, 1);
    expect(views.single.hasSprite, isTrue,
        reason: 'platform_tile.png가 이제 번들에 있으므로 타일 스프라이트를 로드해야 한다');
  });

  test(
      '없는 에셋 경로는 매니페스트에 없다 - onLoad가 Sprite.load 없이 벡터 폴백으로 떨어지는 근거',
      () async {
    // 카탈로그 14종 + basket + button + platform 전부 실물 아트가 생겨(위 두
    // testWidgets 참고) 이제 실제 프리셋/파트로는 "아트 없음" 경로를 더 이상
    // 재현할 수 없다. 대신 onLoad를 지키는 매니페스트 게이트
    // (`if (!manifest.contains(...)) return;`, part_view.dart PartView.onLoad
    // 참고)는 이미 공개돼 있는 loadAssetManifestPaths()로 직접 검증 가능하다 -
    // 가짜 매니페스트를 주입하는 프레임워크 없이, 존재하지 않는 경로가 실제
    // 번들 매니페스트에 없다는 사실 자체가 "Sprite.load 없이 벡터 폴백"을
    // 계속 보장한다는 근거다.
    final manifest = await loadAssetManifestPaths();
    expect(
        manifest.contains('assets/images/parts/__nonexistent__.png'), isFalse);
  });
}

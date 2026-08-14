import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/game/part_view.dart';
import 'package:piyak_science/game/piyak_game.dart';
import 'package:piyak_science/sim/catalog.dart';

import '../sim/helpers.dart';

// 이미지 에셋 14종(부품 12 + 목표물 2) 전체의 json id. platform은 발주서에
// 없음(계속 도형) - 일부러 빠져 있다.
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

  testWidgets('아트가 없는 도형(platform)은 여전히 벡터 폴백이고 크래시하지 않는다',
      (t) async {
    // platform은 발주서 14종에 없다(의도적으로 계속 도형) - 손맛 패스가
    // part_view.dart의 _spriteRelPath에 선택적 타일 스프라이트 경로
    // ('parts/platform_tile.png')를 추가했지만, 그 파일이 아직 매니페스트에
    // 없는 동안은 onLoad의 manifest.contains 체크에서 조용히 걸러져
    // Sprite.load 자체를 타지 않는다(실제 PNG 디코드가 없으므로 위 테스트와
    // 달리 runAsync 없이 기존 pump 관례만으로 충분하다). 여기까지 크래시
    // 없이 렌더됐다는 것 자체가 "도형 렌더 유지"의 증거.
    final s = stage('{"type":"platform","x":8,"y":8,"angle":0,"w":4}', '',
        '{"type":"plank","x":0,"y":0,"angle":0}');

    final game = PiyakGame(s);
    await t.pumpWidget(GameWidget(game: game));
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }

    final views = game.world.children.whereType<PartView>().toList();
    expect(views.length, 1);
    expect(views.single.hasSprite, isFalse,
        reason: '아직 platform_tile.png가 번들에 없으므로 도형 폴백이어야 한다');
  });
}

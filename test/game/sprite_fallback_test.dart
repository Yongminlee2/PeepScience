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
  testWidgets('이미지 에셋이 하나도 없어도 게임이 크래시 없이 뜨고 전부 도형 폴백을 쓴다',
      (t) async {
    final preset = [
      for (var i = 0; i < _ids.length; i++)
        '{"type":"${_ids[i]}","x":${i + 1},"y":1,"angle":0}'
    ].join(',');
    final s = stage(preset, '', '{"type":"plank","x":0,"y":0,"angle":0}');

    final game = PiyakGame(s);
    await t.pumpWidget(GameWidget(game: game));
    // PartView.onLoad가 이제 AssetManifest를 비동기로 조회한다 - 완전히
    // 가라앉을 때까지 여러 프레임 펌프 (placement_test.dart의 선례와 동일한
    // 이유: flutter test의 FakeAsync에서 game.ready()는 데드락한다).
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }

    // 에셋 0개 상태: 매니페스트에 14종 스프라이트 경로가 하나도 없어야 한다.
    final manifest = await loadAssetManifestPaths();
    for (final id in _ids) {
      expect(manifest.contains('assets/images/parts/$id.png'), isFalse,
          reason: '$id.png는 아직 없어야 한다');
    }

    // 실제로 뜬 PartView 14개 전부 "스프라이트 없음"으로 폴백해야 한다 -
    // 크래시 없이 여기까지 렌더됐다는 것 자체가 "도형 렌더 유지"의 증거.
    final views = game.world.children.whereType<PartView>().toList();
    expect(views.length, _ids.length);
    for (final v in views) {
      expect(v.hasSprite, isFalse);
    }
  });
}

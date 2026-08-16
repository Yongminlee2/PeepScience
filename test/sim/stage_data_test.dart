import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/stage_data.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/placement_rules.dart';
import 'dart:convert';

const sample = '''{"id":"w1_s01","world":1,"index":1,
  "goal":{"type":"ball_in_basket"},
  "preset":[{"type":"platform","x":8,"y":7.2,"angle":0,"w":15.5},
            {"type":"basket","x":13,"y":6.7,"angle":0},
            {"type":"rubber_ball","x":1.5,"y":1,"angle":0}],
  "tray":[{"type":"plank","count":1}],
  "solution":[{"type":"plank","x":8.5,"y":5.5,"angle":15}]}''';

void main() {
  test('파싱 왕복', () {
    final s = StageData.fromJson(jsonDecode(sample));
    expect(s.id, 'w1_s01');
    expect(s.goal.type, GoalType.ballInBasket);
    expect(s.tray.single.type, PartType.plank);
    expect(s.solution.single.angleDeg, 15);
    final again = StageData.fromJson(s.toJson());
    expect(again.preset.length, 3);
  });
  test('모르는 부품 id는 거부', () {
    final bad = sample.replaceFirst('"plank"', '"rocket"');
    expect(() => StageData.fromJson(jsonDecode(bad)), throwsFormatException);
  });
  test('solution 비면 거부', () {
    final bad = sample.replaceFirst(
      '"solution":[{"type":"plank","x":8.5,"y":5.5,"angle":15}]',
      '"solution":[]',
    );
    expect(() => StageData.fromJson(jsonDecode(bad)), throwsFormatException);
  });
  test('카탈로그: 회전 가능 부품은 plank·fan뿐', () {
    final rot = PartType.values.where((p) => Catalog.of(p).rotatable).toSet();
    expect(rot, {PartType.plank, PartType.fan});
  });
  test('회전 불가 부품의 사람이 만들 수 없는 정답 각도는 거부', () {
    final issue = solutionPlacementIssue(const [], [
      Placement(type: PartType.trampoline, x: 5, y: 5, angleDeg: -4),
    ]);
    expect(issue, contains('cannot rotate'));
  });
  test('에러 메시지에 스테이지 id 포함', () {
    final bad = sample.replaceFirst('"plank"', '"rocket"');
    expect(
      () => StageData.fromJson(jsonDecode(bad)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('w1_s01:'),
        ),
      ),
    );
  });

  test('연쇄 반응·예측·별 도전 메타데이터 왕복', () {
    final json = jsonDecode(sample) as Map<String, dynamic>;
    json['feature'] = 'chain_reaction';
    json['prediction'] = {'answer': 'metal_ball'};
    json['challenge'] = {
      'part_limit': 2,
      'collectible_star': {'x': 7.5, 'y': 4.25},
    };
    final stage = StageData.fromJson(json);
    expect(stage.feature, StageFeature.chainReaction);
    expect(stage.prediction!.answer, PartType.metalBall);
    expect(stage.challenge!.partLimit, 2);
    expect(stage.challenge!.collectibleStar!.x, 7.5);

    final again = StageData.fromJson(stage.toJson());
    expect(again.feature, StageFeature.chainReaction);
    expect(again.prediction!.answer, PartType.metalBall);
    expect(again.challenge!.collectibleStar!.y, 4.25);
  });

  test('예측 답은 고무공 또는 쇠공만 허용', () {
    final json = jsonDecode(sample) as Map<String, dynamic>;
    json['prediction'] = {'answer': 'plank'};
    expect(() => StageData.fromJson(json), throwsFormatException);
  });
}

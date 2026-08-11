import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/stage_data.dart';
import 'package:piyak_science/sim/catalog.dart';
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
    final bad = sample.replaceFirst('"solution":[{"type":"plank","x":8.5,"y":5.5,"angle":15}]',
        '"solution":[]');
    expect(() => StageData.fromJson(jsonDecode(bad)), throwsFormatException);
  });
  test('카탈로그: 회전 가능 부품은 plank·fan뿐', () {
    final rot = PartType.values.where((p) => Catalog.of(p).rotatable).toSet();
    expect(rot, {PartType.plank, PartType.fan});
  });
}

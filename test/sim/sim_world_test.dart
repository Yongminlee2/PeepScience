import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/sim_world.dart';
import 'package:piyak_science/sim/stage_data.dart';
import 'dart:convert';

StageData stage(String preset, String tray, String sol,
        {String goal = 'ball_in_basket'}) =>
    StageData.fromJson(jsonDecode('{"id":"t","world":1,"index":1,'
        '"goal":{"type":"$goal"},"preset":[$preset],"tray":[$tray],"solution":[$sol]}'));

void main() {
  test('경사로만으로는 미달, 솔루션 널빤지를 놓으면 클리어', () {
    final s = stage(
      '{"type":"platform","x":8,"y":7.2,"angle":0,"w":15.5},'
      '{"type":"platform","x":3,"y":3,"angle":20,"w":4},'
      '{"type":"basket","x":13,"y":6.7,"angle":0},'
      '{"type":"rubber_ball","x":1.5,"y":1,"angle":0}',
      '{"type":"plank","count":1}',
      '{"type":"plank","x":11.0,"y":6.0,"angle":-20}',
    );
    expect(SimWorld.verify(s, const []), isFalse);        // 배치 없이는 실패
    expect(SimWorld.verify(s, s.solution), isTrue);       // 정답 배치는 클리어
  });
  test('화면 밖으로 떨어진 물체는 제거된다', () {
    final s = stage('{"type":"rubber_ball","x":8,"y":1,"angle":0},'
        '{"type":"basket","x":1,"y":8.6,"angle":0}', '{"type":"plank","count":1}',
        '{"type":"plank","x":1,"y":1,"angle":0}');
    final w = SimWorld(s, const []);
    for (var i = 0; i < 600; i++) { w.step(); }
    expect(w.world.bodies.where((b) => (b.userData as PartTag?)?.part != null), isEmpty);
  });
}

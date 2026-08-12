import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/editor/editor_screen.dart';
import 'package:piyak_science/sim/catalog.dart';
import 'package:piyak_science/sim/stage_data.dart';

void main() {
  group('EditorState.exportJson', () {
    test('round-trips through StageData.fromJson with every field intact',
        () {
      final state = EditorState()
        ..world = 2
        ..index = 5
        ..goal = GoalType.popBalloons
        ..preset.addAll([
          PresetObject(type: 'platform', x: 8.0, y: 7.2, angleDeg: 0, w: 15.5),
          PresetObject(type: 'basket', x: 13.0, y: 6.7, angleDeg: 20),
        ])
        ..tray.add(TrayEntry(type: PartType.plank, count: 3))
        ..solution
            .add(Placement(type: PartType.plank, x: 8.5, y: 5.5, angleDeg: 15));

      final json = state.exportJson();
      final data =
          StageData.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(data.id, 'w2_s05');
      expect(data.world, 2);
      expect(data.index, 5);
      expect(data.goal.type, GoalType.popBalloons);
      expect(data.preset.length, 2);
      expect(data.preset[0].type, 'platform');
      expect(data.preset[0].w, 15.5);
      expect(data.preset[1].type, 'basket');
      expect(data.preset[1].angleDeg, 20);
      expect(data.tray.single.type, PartType.plank);
      expect(data.tray.single.count, 3);
      expect(data.solution.single.type, PartType.plank);
      expect(data.solution.single.x, 8.5);
      expect(data.solution.single.angleDeg, 15);
    });

    test('throws instead of exporting JSON that fromJson would reject '
        '(empty solution)', () {
      final state = EditorState()
        ..preset.add(PresetObject(type: 'basket', x: 1, y: 1, angleDeg: 0))
        ..tray.add(TrayEntry(type: PartType.plank, count: 1));
      // solution left empty on purpose.

      expect(() => state.exportJson(), throwsFormatException);
    });
  });

  group('EditorState.importJson', () {
    test('parses an exported JSON string back into editor state', () {
      final original = EditorState()
        ..world = 3
        ..index = 7
        ..goal = GoalType.pressButton
        ..preset.add(PresetObject(type: 'button', x: 4, y: 4, angleDeg: 0))
        ..tray.add(TrayEntry(type: PartType.rubberBall, count: 2))
        ..solution.add(
            Placement(type: PartType.rubberBall, x: 4, y: 1, angleDeg: 0));
      final json = original.exportJson();

      final imported = EditorState();
      imported.importJson(json);

      expect(imported.world, 3);
      expect(imported.index, 7);
      expect(imported.goal, GoalType.pressButton);
      expect(imported.preset.single.type, 'button');
      expect(imported.tray.single.type, PartType.rubberBall);
      expect(imported.tray.single.count, 2);
      expect(imported.solution.single.x, 4);
      expect(imported.solution.single.angleDeg, 0);
    });
  });
}

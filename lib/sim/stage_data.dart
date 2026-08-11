import 'catalog.dart';

class Placement {
  final PartType type;
  final double x;
  final double y;
  final double angleDeg;

  Placement({
    required this.type,
    required this.x,
    required this.y,
    required this.angleDeg,
  });

  Map<String, dynamic> toJson() => {
        'type': jsonIdOf(type),
        'x': x,
        'y': y,
        'angle': angleDeg,
      };

  static Placement fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'];
    if (typeStr is! String) {
      throw FormatException('Placement type must be a string, got $typeStr');
    }
    final type = partTypeFromJson(typeStr);
    final xVal = j['x'];
    final yVal = j['y'];
    final angleVal = j['angle'];

    if (xVal is! num || yVal is! num || angleVal is! num) {
      throw FormatException(
          'Placement x, y, angle must be numbers, got x:$xVal, y:$yVal, angle:$angleVal');
    }

    return Placement(
      type: type,
      x: xVal.toDouble(),
      y: yVal.toDouble(),
      angleDeg: angleVal.toDouble(),
    );
  }
}

class TrayEntry {
  final PartType type;
  final int count;

  TrayEntry({
    required this.type,
    required this.count,
  });

  Map<String, dynamic> toJson() => {
        'type': jsonIdOf(type),
        'count': count,
      };

  static TrayEntry fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'];
    if (typeStr is! String) {
      throw FormatException('TrayEntry type must be a string, got $typeStr');
    }
    final type = partTypeFromJson(typeStr);
    final count = j['count'];

    if (count is! int) {
      throw FormatException('TrayEntry count must be an int, got $count');
    }

    return TrayEntry(type: type, count: count);
  }
}

class PresetObject {
  final String type; // "platform", "basket", "button", or part type (PartType converted to JSON)
  final double x;
  final double y;
  final double angleDeg;
  final double? w; // for platform

  PresetObject({
    required this.type,
    required this.x,
    required this.y,
    required this.angleDeg,
    this.w,
  });

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'type': type,
      'x': x,
      'y': y,
      'angle': angleDeg,
    };
    if (w != null) {
      result['w'] = w!;
    }
    return result;
  }

  static PresetObject fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'];
    if (typeStr is! String) {
      throw FormatException('PresetObject type must be a string, got $typeStr');
    }

    // Validate that it's either a known preset type or a valid part type
    final knownPresets = {'platform', 'basket', 'button'};
    if (!knownPresets.contains(typeStr)) {
      // Try to parse as a part type to validate it
      try {
        partTypeFromJson(typeStr);
      } catch (e) {
        throw FormatException('Unknown preset type: $typeStr');
      }
    }

    final xVal = j['x'];
    final yVal = j['y'];
    final angleVal = j['angle'];

    if (xVal is! num || yVal is! num || angleVal is! num) {
      throw FormatException(
          'PresetObject x, y, angle must be numbers, got x:$xVal, y:$yVal, angle:$angleVal');
    }

    final w = j['w'];
    final wValue = w != null ? (w as num).toDouble() : null;

    return PresetObject(
      type: typeStr,
      x: xVal.toDouble(),
      y: yVal.toDouble(),
      angleDeg: angleVal.toDouble(),
      w: wValue,
    );
  }
}

class GoalSpec {
  final GoalType type;

  GoalSpec({required this.type});

  Map<String, dynamic> toJson() => {
        'type': goalJsonIdOf(type),
      };

  static GoalSpec fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'];
    if (typeStr is! String) {
      throw FormatException('GoalSpec type must be a string, got $typeStr');
    }
    final type = goalTypeFromJson(typeStr);
    return GoalSpec(type: type);
  }
}

class StageData {
  final String id;
  final int world;
  final int index;
  final GoalSpec goal;
  final List<PresetObject> preset;
  final List<TrayEntry> tray;
  final List<Placement> solution;

  StageData({
    required this.id,
    required this.world,
    required this.index,
    required this.goal,
    required this.preset,
    required this.tray,
    required this.solution,
  });

  static StageData fromJson(Map<String, dynamic> j) {
    try {
      final id = j['id'];
      if (id is! String || id.isEmpty) {
        throw FormatException('id must be a non-empty string');
      }

      final world = j['world'];
      if (world is! int) {
        throw FormatException('$id: world must be an integer');
      }

      final index = j['index'];
      if (index is! int) {
        throw FormatException('$id: index must be an integer');
      }

      final goalJson = j['goal'];
      if (goalJson is! Map<String, dynamic>) {
        throw FormatException('$id: goal must be an object');
      }
      final goal = GoalSpec.fromJson(goalJson);

      final presetJson = j['preset'];
      if (presetJson is! List) {
        throw FormatException('$id: preset must be an array');
      }
      final preset = <PresetObject>[];
      for (final p in presetJson) {
        if (p is! Map<String, dynamic>) {
          throw FormatException('$id: preset item must be an object');
        }
        preset.add(PresetObject.fromJson(p));
      }

      final trayJson = j['tray'];
      if (trayJson is! List) {
        throw FormatException('$id: tray must be an array');
      }
      final tray = <TrayEntry>[];
      for (final t in trayJson) {
        if (t is! Map<String, dynamic>) {
          throw FormatException('$id: tray item must be an object');
        }
        final entry = TrayEntry.fromJson(t);
        if (entry.count < 1) {
          throw FormatException('$id: tray count must be >= 1');
        }
        tray.add(entry);
      }

      final solutionJson = j['solution'];
      if (solutionJson is! List) {
        throw FormatException('$id: solution must be an array');
      }
      if (solutionJson.isEmpty) {
        throw FormatException('$id: solution cannot be empty');
      }
      final solution = <Placement>[];
      for (final s in solutionJson) {
        if (s is! Map<String, dynamic>) {
          throw FormatException('$id: solution item must be an object');
        }
        solution.add(Placement.fromJson(s));
      }

      return StageData(
        id: id,
        world: world,
        index: index,
        goal: goal,
        preset: preset,
        tray: tray,
        solution: solution,
      );
    } catch (e) {
      if (e is FormatException) {
        rethrow;
      }
      throw FormatException('Failed to parse StageData: $e');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'world': world,
        'index': index,
        'goal': goal.toJson(),
        'preset': preset.map((p) => p.toJson()).toList(),
        'tray': tray.map((t) => t.toJson()).toList(),
        'solution': solution.map((s) => s.toJson()).toList(),
      };
}

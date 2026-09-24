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
        'Placement x, y, angle must be numbers, got x:$xVal, y:$yVal, angle:$angleVal',
      );
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

  TrayEntry({required this.type, required this.count});

  Map<String, dynamic> toJson() => {'type': jsonIdOf(type), 'count': count};

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
  final String
  type; // "platform", "basket", "button", or part type (PartType converted to JSON)
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
        'PresetObject x, y, angle must be numbers, got x:$xVal, y:$yVal, angle:$angleVal',
      );
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

  Map<String, dynamic> toJson() => {'type': goalJsonIdOf(type)};

  static GoalSpec fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'];
    if (typeStr is! String) {
      throw FormatException('GoalSpec type must be a string, got $typeStr');
    }
    final type = goalTypeFromJson(typeStr);
    return GoalSpec(type: type);
  }
}

/// Optional stage presentation hook. It never changes physics; the game
/// layer uses it to explain a satisfying multi-step cause/effect setup.
enum StageFeature { chainReaction }

StageFeature stageFeatureFromJson(String id) => switch (id) {
  'chain_reaction' => StageFeature.chainReaction,
  _ => throw FormatException('Unknown stage feature: $id'),
};

String stageFeatureJsonIdOf(StageFeature feature) => switch (feature) {
  StageFeature.chainReaction => 'chain_reaction',
};

/// A lightweight predict-before-running prompt. The first experiment uses
/// the two ball materials already in the catalog so the prediction is tied
/// to real physical behavior, not a quiz detached from play.
class PredictionSpec {
  final PartType answer;

  const PredictionSpec({required this.answer});

  Map<String, dynamic> toJson() => {'answer': jsonIdOf(answer)};

  static PredictionSpec fromJson(Map<String, dynamic> j) {
    final raw = j['answer'];
    if (raw is! String) {
      throw FormatException('Prediction answer must be a string');
    }
    final answer = partTypeFromJson(raw);
    if (answer != PartType.rubberBall && answer != PartType.metalBall) {
      throw FormatException(
        'Prediction answer must be rubber_ball or metal_ball',
      );
    }
    return PredictionSpec(answer: answer);
  }
}

class CollectibleStarSpec {
  final double x;
  final double y;

  const CollectibleStarSpec({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  static CollectibleStarSpec fromJson(Map<String, dynamic> j) {
    final x = j['x'];
    final y = j['y'];
    if (x is! num || y is! num) {
      throw FormatException('Collectible star x and y must be numbers');
    }
    return CollectibleStarSpec(x: x.toDouble(), y: y.toDouble());
  }
}

/// Optional mastery goals shown after the ordinary clear condition. Clearing
/// always remains enough to unlock the next stage; these only add replay
/// motivation and never gate progression.
class ChallengeSpec {
  final int partLimit;
  final CollectibleStarSpec? collectibleStar;

  const ChallengeSpec({required this.partLimit, this.collectibleStar});

  Map<String, dynamic> toJson() => {
    'part_limit': partLimit,
    if (collectibleStar != null) 'collectible_star': collectibleStar!.toJson(),
  };

  static ChallengeSpec fromJson(Map<String, dynamic> j) {
    final partLimit = j['part_limit'];
    if (partLimit is! int || partLimit < 1) {
      throw FormatException('Challenge part_limit must be an int >= 1');
    }
    final rawStar = j['collectible_star'];
    if (rawStar != null && rawStar is! Map<String, dynamic>) {
      throw FormatException('Challenge collectible_star must be an object');
    }
    return ChallengeSpec(
      partLimit: partLimit,
      collectibleStar: rawStar == null
          ? null
          : CollectibleStarSpec.fromJson(rawStar),
    );
  }
}

/// 공(고무공·쇠공)을 놓을 수 있는 자리. 없으면 제한이 없다.
///
/// 공은 트레이에서 꺼내 아무 데나 놓을 수 있어서, 중력으로 목표에 닿는 판은
/// 장치를 만들지 않고 공을 목표 근처에 떨궈 버리면 그냥 깨진다. 판마다 공을
/// 놓을 구역을 정해 그 구멍을 막는다. 널빤지·톱니 같은 나머지 부품은 이
/// 제한을 받지 않는다.
class BallZone {
  /// 구역 중심과 크기(월드 단위 m).
  final double x, y, w, h;

  const BallZone({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  bool contains(double px, double py) =>
      (px - x).abs() <= w / 2 && (py - y).abs() <= h / 2;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  static BallZone fromJson(Map<String, dynamic> j) {
    double num_(String k) {
      final v = j[k];
      if (v is! num) throw FormatException('ballZone.$k must be a number');
      return v.toDouble();
    }

    final zone = BallZone(x: num_('x'), y: num_('y'), w: num_('w'), h: num_('h'));
    if (zone.w <= 0 || zone.h <= 0) {
      throw const FormatException('ballZone w/h must be positive');
    }
    return zone;
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
  final StageFeature? feature;
  final PredictionSpec? prediction;
  final ChallengeSpec? challenge;
  final BallZone? ballZone;

  StageData({
    required this.id,
    required this.world,
    required this.index,
    required this.goal,
    required this.preset,
    required this.tray,
    required this.solution,
    this.feature,
    this.prediction,
    this.challenge,
    this.ballZone,
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
      late final GoalSpec goal;
      try {
        goal = GoalSpec.fromJson(goalJson);
      } on FormatException catch (e) {
        throw FormatException('$id: ${e.message}');
      }

      final presetJson = j['preset'];
      if (presetJson is! List) {
        throw FormatException('$id: preset must be an array');
      }
      final preset = <PresetObject>[];
      for (final p in presetJson) {
        if (p is! Map<String, dynamic>) {
          throw FormatException('$id: preset item must be an object');
        }
        try {
          preset.add(PresetObject.fromJson(p));
        } on FormatException catch (e) {
          throw FormatException('$id: ${e.message}');
        }
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
        late final TrayEntry entry;
        try {
          entry = TrayEntry.fromJson(t);
        } on FormatException catch (e) {
          throw FormatException('$id: ${e.message}');
        }
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
        try {
          solution.add(Placement.fromJson(s));
        } on FormatException catch (e) {
          throw FormatException('$id: ${e.message}');
        }
      }

      final featureJson = j['feature'];
      if (featureJson != null && featureJson is! String) {
        throw FormatException('$id: feature must be a string');
      }
      final feature = featureJson == null
          ? null
          : stageFeatureFromJson(featureJson);

      final predictionJson = j['prediction'];
      if (predictionJson != null && predictionJson is! Map<String, dynamic>) {
        throw FormatException('$id: prediction must be an object');
      }
      final prediction = predictionJson == null
          ? null
          : PredictionSpec.fromJson(predictionJson);

      final challengeJson = j['challenge'];
      if (challengeJson != null && challengeJson is! Map<String, dynamic>) {
        throw FormatException('$id: challenge must be an object');
      }
      final challenge = challengeJson == null
          ? null
          : ChallengeSpec.fromJson(challengeJson);

      final ballZoneJson = j['ballZone'];
      if (ballZoneJson != null && ballZoneJson is! Map<String, dynamic>) {
        throw FormatException('$id: ballZone must be an object');
      }
      final ballZone = ballZoneJson == null
          ? null
          : BallZone.fromJson(ballZoneJson);

      return StageData(
        id: id,
        world: world,
        index: index,
        goal: goal,
        preset: preset,
        tray: tray,
        solution: solution,
        feature: feature,
        prediction: prediction,
        challenge: challenge,
        ballZone: ballZone,
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
    if (feature != null) 'feature': stageFeatureJsonIdOf(feature!),
    if (prediction != null) 'prediction': prediction!.toJson(),
    if (challenge != null) 'challenge': challenge!.toJson(),
    if (ballZone != null) 'ballZone': ballZone!.toJson(),
  };
}

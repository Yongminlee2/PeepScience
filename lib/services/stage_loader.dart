import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../sim/stage_data.dart';

/// Thrown by [StageLoader] for any failure to produce a [StageData] for a
/// stage id - missing asset or malformed JSON/schema alike, so callers have
/// exactly one exception type to catch regardless of cause.
class StageLoadError implements Exception {
  StageLoadError(this.stageId, this.message);

  final String stageId;
  final String message;

  @override
  String toString() => 'StageLoadError($stageId): $message';
}

/// Loads stage JSON from the asset bundle. `lib/sim/` stays pure Dart (no
/// Flutter imports - see stage_data.dart), so the [rootBundle] read lives
/// here instead, in lib/services/ alongside progress.dart/sound.dart (both
/// also Flutter-facing I/O wrappers around pure sim/ data).
class StageLoader {
  StageLoader._();

  /// Reads `assets/stages/<id>.json` and parses it. Note: those assets
  /// don't exist yet (task 13 authors them) - until then this always throws
  /// [StageLoadError], by design (see [parse] for the seam tests use
  /// instead, to exercise parsing without depending on real assets).
  static Future<StageData> load(String id) async {
    final String raw;
    try {
      raw = await rootBundle.loadString('assets/stages/$id.json');
    } catch (e) {
      throw StageLoadError(id, 'asset load failed: $e');
    }
    return parse(id, raw);
  }

  /// Pure JSON-string -> [StageData], no asset I/O. The unit-testable seam:
  /// callers that want to check the parse-failure path inject a JSON string
  /// directly instead of needing a real (today, nonexistent) stage asset.
  static StageData parse(String id, String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      return StageData.fromJson(decoded as Map<String, dynamic>);
    } catch (e) {
      throw StageLoadError(id, 'parse failed: $e');
    }
  }
}

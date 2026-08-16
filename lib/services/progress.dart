import 'package:shared_preferences/shared_preferences.dart';
import 'package:piyak_science/sim/registry.dart';

/// Manages stage progression and cleared stage persistence.
class ProgressStore {
  final SharedPreferences _prefs;

  ProgressStore._(this._prefs);

  /// Initialize ProgressStore from shared_preferences.
  static Future<ProgressStore> init() async {
    final prefs = await SharedPreferences.getInstance();
    return ProgressStore._(prefs);
  }

  /// Get set of cleared stage IDs.
  Future<Set<String>> cleared() async {
    final list = _prefs.getStringList('cleared_v1') ?? [];
    return list.toSet();
  }

  /// Mark a stage as cleared and persist.
  Future<void> markCleared(String id) async {
    final list = _prefs.getStringList('cleared_v1') ?? [];
    if (!list.contains(id)) {
      list.add(id);
      await _prefs.setStringList('cleared_v1', list);
    }
  }

  /// The four-page first-experiment guide is shown automatically once.
  /// It remains reachable from the in-game help button after this flag is
  /// set, so skipping never makes the instructions permanently unavailable.
  Future<bool> tutorialSeen() async =>
      _prefs.getBool('tutorial_seen_v1') ?? false;

  Future<void> markTutorialSeen() async {
    await _prefs.setBool('tutorial_seen_v1', true);
  }

  /// Best mastery result per stage. Stored as compact `stageId:count`
  /// entries so the format remains inspectable and can coexist with the
  /// original cleared_v1 list without a migration.
  Future<Map<String, int>> stars() async {
    final raw = _prefs.getStringList('stars_v1') ?? const [];
    final result = <String, int>{};
    for (final entry in raw) {
      final split = entry.lastIndexOf(':');
      if (split <= 0) continue;
      final value = int.tryParse(entry.substring(split + 1));
      if (value == null || value < 1 || value > 3) continue;
      result[entry.substring(0, split)] = value;
    }
    // Before stars_v1 existed, a clear had no mastery breakdown. Preserve
    // those players' completed-looking grid instead of turning every old
    // green check into an unexplained empty 0/3 state.
    for (final id in _prefs.getStringList('cleared_v1') ?? const <String>[]) {
      result.putIfAbsent(id, () => 3);
    }
    return result;
  }

  /// Persists only improvements; replaying a stage can never lower a
  /// previously earned result.
  Future<void> markStars(String id, int count) async {
    final clamped = count.clamp(1, 3);
    final current = await stars();
    if ((current[id] ?? 0) >= clamped) return;
    current[id] = clamped;
    final encoded = current.entries.map((e) => '${e.key}:${e.value}').toList()
      ..sort();
    await _prefs.setStringList('stars_v1', encoded);
  }

  /// Check if a stage is unlocked based on progression rules.
  /// Unlocked if:
  /// - it's the first stage in stageOrder, OR
  /// - the previous stage in stageOrder is in cleared set
  bool isUnlocked(String id, Set<String> cleared) {
    // First stage is always unlocked
    if (stageOrder.isNotEmpty && id == stageOrder[0]) {
      return true;
    }

    // Find this stage's index
    final index = stageOrder.indexOf(id);
    if (index <= 0) {
      return false; // Not in registry or is first (which was already checked)
    }

    // Check if previous stage is cleared
    final prevId = stageOrder[index - 1];
    return cleared.contains(prevId);
  }
}

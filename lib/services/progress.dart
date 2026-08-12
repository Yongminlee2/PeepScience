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

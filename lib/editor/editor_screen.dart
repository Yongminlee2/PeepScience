import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../game/input.dart'
    show kFieldMinX, kFieldMaxX, kFieldMinY, kFieldMaxY;
import '../game/piyak_game.dart';
import '../sim/catalog.dart';
import '../sim/placement_rules.dart' show solutionPlacementIssue;
import '../sim/stage_data.dart';

/// All editor-authored stage data, minus id (derived from [world]/[index] -
/// same `w<world>_s<index2>` scheme as sim/registry.dart's `stageOrder` and
/// home_screen.dart's own `_stageId`).
///
/// Deliberately Flutter-free (only sim/ types) so [exportJson]/[importJson]
/// are plain functions test/editor/export_test.dart can call without ever
/// pumping a widget - manual UI (drag/tap placement) isn't covered there by
/// design (brief: "UI 드래그까지는 테스트하지 않는다").
class EditorState {
  int world = 1;
  int index = 1;
  GoalType goal = GoalType.ballInBasket;

  /// Stage terrain/goal-objects/preset-dynamic-parts - authored in the
  /// screen's "preset" mode.
  final List<PresetObject> preset = [];

  /// The REAL per-stage tray the player gets (author-configured via +/-
  /// steppers) - distinct from the *unlimited* tray the live preview game
  /// hands out while testing (see [_EditorScreenState._buildGame]).
  final List<TrayEntry> tray = [];

  /// Author's own solution placements, snapshotted from the live preview
  /// game by the "Record Solution" button.
  final List<Placement> solution = [];

  String get stageId => 'w${world}_s${index.toString().padLeft(2, '0')}';

  int trayCount(PartType t) {
    for (final e in tray) {
      if (e.type == t) return e.count;
    }
    return 0;
  }

  void setTrayCount(PartType t, int count) {
    tray.removeWhere((e) => e.type == t);
    if (count > 0) tray.add(TrayEntry(type: t, count: count));
  }

  StageData _toStageData() => StageData(
        id: stageId,
        world: world,
        index: index,
        goal: GoalSpec(type: goal),
        preset: List.of(preset),
        tray: List.of(tray),
        solution: List.of(solution),
      );

  /// Serializes to StageData JSON, validating the round-trip through
  /// [StageData.fromJson] before returning - throws [FormatException] (e.g.
  /// "solution cannot be empty") instead of ever handing back JSON that
  /// would fail that same validation later. Callers (the Export button)
  /// catch this and warn instead of copying broken JSON to the clipboard.
  ///
  /// Also refuses (same exception type) a solution the game's own
  /// canPlaceAt rules would reject - see [solutionPlacementIssue]. Recording
  /// the solution via the live preview game (parts mode's drag/drop) can
  /// never produce one of these (every placement there already went through
  /// canPlaceAt); this guards hand-edited/imported JSON and copy-paste
  /// mistakes between stages instead.
  String exportJson() {
    final data = _toStageData();
    final placementIssue = solutionPlacementIssue(
      data.preset,
      data.solution,
      ballZone: data.ballZone,
    );
    if (placementIssue != null) {
      throw FormatException(placementIssue);
    }
    final str = const JsonEncoder.withIndent('  ').convert(data.toJson());
    StageData.fromJson(jsonDecode(str) as Map<String, dynamic>); // validate
    return str;
  }

  /// Parses [json] (as produced by [exportJson], or any hand-authored stage
  /// JSON) back into this state's fields, replacing every field wholesale.
  /// Throws [FormatException] on invalid JSON, same as [StageData.fromJson].
  void importJson(String json) {
    final data = StageData.fromJson(jsonDecode(json) as Map<String, dynamic>);
    world = data.world;
    index = data.index;
    goal = data.goal.type;
    preset
      ..clear()
      ..addAll(data.preset);
    tray
      ..clear()
      ..addAll(data.tray);
    solution
      ..clear()
      ..addAll(data.solution);
  }
}

/// Debug-only stage editor (kDebugMode-gated at the call site in
/// home_screen.dart - this widget itself has no gate, so it must never be
/// referenced outside an `if (kDebugMode)` branch or a release build would
/// pull it back in).
///
/// Two modes, toggled by the top bar button:
/// - parts: the real [PiyakGame] with every [PartType] in the tray at an
///   effectively unlimited count - author drags/rotates/deletes/runs a
///   candidate solution with the exact same engine and controls a player
///   uses.
/// - preset: a lightweight tap-to-place canvas (NOT PiyakGame - presets
///   include plain-string kinds like "platform"/"basket" that don't fit
///   PiyakGame's PartType-only tray) for authoring `stage.preset`, plus a
///   fields panel to fine-tune the selected object's x/y/angle/w.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _EditorMode { parts, preset }

/// Tray count handed to the live preview [PiyakGame] for every part type -
/// "unlimited" in practice (an author testing a solution should never run
/// dry mid-experiment). The stage's real tray is authored separately via
/// [EditorState.tray] / the +/- steppers, and is what actually gets
/// exported.
const int _kUnlimitedTrayCount = 99;

final List<String> _kPresetTypeOptions = [
  'platform',
  'basket',
  'button',
  for (final t in PartType.values) jsonIdOf(t),
];

class _EditorScreenState extends State<EditorScreen> {
  final EditorState _state = EditorState();
  _EditorMode _mode = _EditorMode.parts;
  late PiyakGame _game = _buildGame();
  String _presetTypeToPlace = 'platform';
  int? _selectedPresetIndex;

  late final _worldCtrl = TextEditingController(text: '${_state.world}');
  late final _indexCtrl = TextEditingController(text: '${_state.index}');

  @override
  void dispose() {
    _worldCtrl.dispose();
    _indexCtrl.dispose();
    super.dispose();
  }

  PiyakGame _buildGame() {
    final stage = StageData(
      id: _state.stageId,
      world: _state.world,
      index: _state.index,
      goal: GoalSpec(type: _state.goal),
      preset: List.of(_state.preset),
      tray: [
        for (final t in PartType.values)
          TrayEntry(type: t, count: _kUnlimitedTrayCount),
      ],
      solution: const [],
    );
    return PiyakGame(stage);
  }

  /// Rebuilds the live preview game from the current [_state] (picking up
  /// preset/goal/world/index edits made while it wasn't mounted) and carries
  /// forward whatever the author already had placed, so a preset tweak
  /// doesn't throw away an in-progress solution attempt. Also switches the
  /// editor into parts mode unconditionally - correct for both call sites
  /// below (`_toggleMode`'s preset->parts branch is already switching;
  /// `_onStageMetaChanged` only calls this when parts mode is already
  /// showing).
  void _enterPartsMode() {
    final old = _game;
    final fresh = _buildGame()..placements.addAll(old.placements);
    setState(() {
      _game = fresh;
      _mode = _EditorMode.parts;
    });
  }

  void _toggleMode() {
    if (_mode == _EditorMode.preset) {
      _enterPartsMode();
    } else {
      setState(() => _mode = _EditorMode.preset);
    }
  }

  /// World/index/goal edits (and importJson) change [_state] fields that the
  /// live preview game only snapshots at construction time - but forcing a
  /// switch to parts mode just to reflect a text field edit would yank the
  /// author out of preset mode while they're mid-placement. Only rebuild
  /// (and thus only touch [_mode]) when parts mode is already showing;
  /// otherwise just setState so the top bar reflects the new value, and
  /// defer the game rebuild to the next explicit switch into parts mode -
  /// same deferral a preset-list edit already gets.
  void _onStageMetaChanged() {
    if (_mode == _EditorMode.parts) {
      _enterPartsMode();
    } else {
      setState(() {});
    }
  }

  void _recordSolution() {
    setState(() {
      _state.solution
        ..clear()
        ..addAll(_game.placements);
    });
    _snack('Solution recorded (${_state.solution.length} placement(s)).');
  }

  Future<void> _export() async {
    final String json;
    try {
      json = _state.exportJson();
    } on FormatException catch (e) {
      _snack('Export refused: ${e.message}');
      return;
    }
    await Clipboard.setData(ClipboardData(text: json));
    debugPrint(json);
    if (!mounted) return;
    _snack('Copied ${json.length} chars to clipboard (also in flutter logs).');
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      _snack('Clipboard is empty.');
      return;
    }
    try {
      _state.importJson(text);
    } on FormatException catch (e) {
      _snack('Import failed: ${e.message}');
      return;
    }
    _worldCtrl.text = '${_state.world}';
    _indexCtrl.text = '${_state.index}';
    _selectedPresetIndex = null;
    _onStageMetaChanged();
    _snack('Imported stage ${_state.stageId}.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setWorld(String v) {
    final n = int.tryParse(v);
    if (n == null) return;
    _state.world = n < 1 ? 1 : n;
    _onStageMetaChanged();
  }

  void _setIndex(String v) {
    final n = int.tryParse(v);
    if (n == null) return;
    _state.index = n < 1 ? 1 : n;
    _onStageMetaChanged();
  }

  void _placePreset(Offset worldM) {
    if (worldM.dx < kFieldMinX ||
        worldM.dx > kFieldMaxX ||
        worldM.dy < kFieldMinY ||
        worldM.dy > kFieldMaxY) {
      _snack('Out of bounds - field is '
          'x:[$kFieldMinX,$kFieldMaxX] y:[$kFieldMinY,$kFieldMaxY].');
      return;
    }
    setState(() {
      _state.preset.add(PresetObject(
        type: _presetTypeToPlace,
        x: worldM.dx,
        y: worldM.dy,
        angleDeg: 0,
        w: _presetTypeToPlace == 'platform' ? 3.0 : null,
      ));
      _selectedPresetIndex = _state.preset.length - 1;
    });
  }

  void _updatePreset(int i,
      {double? x, double? y, double? angleDeg, double? w}) {
    final p = _state.preset[i];
    setState(() {
      _state.preset[i] = PresetObject(
        type: p.type,
        x: x ?? p.x,
        y: y ?? p.y,
        angleDeg: angleDeg ?? p.angleDeg,
        w: w ?? p.w,
      );
    });
  }

  void _deletePreset(int i) {
    setState(() {
      _state.preset.removeAt(i);
      _selectedPresetIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Stage Editor - ${_state.stageId}')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _worldCtrl,
                      decoration: const InputDecoration(labelText: 'World'),
                      keyboardType: TextInputType.number,
                      onSubmitted: _setWorld,
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _indexCtrl,
                      decoration: const InputDecoration(labelText: 'Index'),
                      keyboardType: TextInputType.number,
                      onSubmitted: _setIndex,
                    ),
                  ),
                  DropdownButton<GoalType>(
                    value: _state.goal,
                    items: [
                      for (final g in GoalType.values)
                        DropdownMenuItem(value: g, child: Text(_goalLabel(g))),
                    ],
                    onChanged: (g) {
                      if (g == null) return;
                      _state.goal = g;
                      _onStageMetaChanged();
                    },
                  ),
                  FilledButton.icon(
                    onPressed: _toggleMode,
                    icon: Icon(_mode == _EditorMode.parts
                        ? Icons.view_in_ar
                        : Icons.grid_on),
                    label: Text(_mode == _EditorMode.parts
                        ? 'Parts Mode'
                        : 'Preset Mode'),
                  ),
                  OutlinedButton(
                    onPressed:
                        _mode == _EditorMode.parts ? _recordSolution : null,
                    child: Text('Record Solution (${_state.solution.length})'),
                  ),
                  OutlinedButton(
                      onPressed: _export, child: const Text('Export')),
                  OutlinedButton(
                      onPressed: _import, child: const Text('Import')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final t in PartType.values) _trayStepper(t),
                ],
              ),
            ),
            if (_mode == _EditorMode.preset)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    const Text('Place: '),
                    DropdownButton<String>(
                      value: _presetTypeToPlace,
                      items: [
                        for (final t in _kPresetTypeOptions)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) =>
                          setState(() => _presetTypeToPlace = v ?? _presetTypeToPlace),
                    ),
                    const SizedBox(width: 12),
                    const Text('tap the field below to add / select'),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _mode == _EditorMode.parts
                      ? GameWidget(game: _game)
                      : _PresetCanvas(
                          items: _state.preset,
                          selectedIndex: _selectedPresetIndex,
                          onPlace: _placePreset,
                          onSelect: (i) =>
                              setState(() => _selectedPresetIndex = i),
                        ),
                ),
              ),
            ),
            if (_mode == _EditorMode.preset) _buildFieldsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _trayStepper(PartType t) {
    final count = _state.trayCount(t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(jsonIdOf(t), style: const TextStyle(fontSize: 11)),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.remove),
            onPressed: count > 0
                ? () => setState(() => _state.setTrayCount(t, count - 1))
                : null,
          ),
          Text('$count'),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _state.setTrayCount(t, count + 1)),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsPanel() {
    final i = _selectedPresetIndex;
    if (i == null || i >= _state.preset.length) return const SizedBox.shrink();
    final p = _state.preset[i];
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(p.type, style: const TextStyle(fontWeight: FontWeight.bold)),
            _numField('X', i, 'x', p.x, (v) => _updatePreset(i, x: v)),
            _numField('Y', i, 'y', p.y, (v) => _updatePreset(i, y: v)),
            _numField('Angle', i, 'a', p.angleDeg,
                (v) => _updatePreset(i, angleDeg: v)),
            if (p.type == 'platform')
              _numField('W', i, 'w', p.w ?? 3.0, (v) => _updatePreset(i, w: v)),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _deletePreset(i),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(String label, int itemIndex, String fieldTag, double value,
      void Function(double) onSet) {
    return SizedBox(
      width: 84,
      child: TextFormField(
        key: ValueKey('${fieldTag}_$itemIndex'),
        initialValue: value.toString(),
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        onFieldSubmitted: (v) {
          final parsed = double.tryParse(v);
          if (parsed != null) onSet(parsed);
        },
      ),
    );
  }
}

String _goalLabel(GoalType g) => switch (g) {
      GoalType.ballInBasket => 'Ball in Basket',
      GoalType.pressButton => 'Press Button',
      GoalType.popBalloons => 'Pop Balloons',
      GoalType.toppleDominoes => 'Topple Dominoes',
    };

/// Conservative axis-aligned half-extents (meters) for a preset object -
/// ignores rotation (unlike input.dart's canPlaceAt boxes), which is fine
/// for this canvas's own tap-to-select hit test and visual box; precise
/// overlap/rotation handling belongs to the real gameplay field, not this
/// authoring aid.
(double, double) _presetHalfExtentsM(PresetObject p) {
  switch (p.type) {
    case 'platform':
      return (p.w! / 2, 0.2);
    case 'basket':
      return (0.5, 0.36);
    case 'button':
      return (0.4, 0.11);
    default:
      final spec = Catalog.of(partTypeFromJson(p.type));
      if (spec.radius != null) return (spec.radius!, spec.radius!);
      return (spec.w! / 2, spec.h! / 2);
  }
}

/// Lightweight tap-to-place canvas for preset mode - deliberately NOT a
/// PiyakGame/Flame component (presets include plain-string kinds like
/// "platform" that don't fit PiyakGame's PartType-only tray/placement
/// machinery). A tap on empty field calls [onPlace] with the world-meter
/// position (the caller decides what type to place there); a tap on an
/// existing object calls [onSelect] with its index instead.
class _PresetCanvas extends StatelessWidget {
  const _PresetCanvas({
    required this.items,
    required this.selectedIndex,
    required this.onPlace,
    required this.onSelect,
  });

  final List<PresetObject> items;
  final int? selectedIndex;
  final void Function(Offset worldM) onPlace;
  final void Function(int index) onSelect;

  static const double _worldWM = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final scale = box.maxWidth / _worldWM;
      return GestureDetector(
        onTapUp: (d) {
          final worldM = Offset(
            d.localPosition.dx / scale,
            d.localPosition.dy / scale,
          );
          final hit = _hitTest(worldM);
          if (hit != null) {
            onSelect(hit);
          } else {
            onPlace(worldM);
          }
        },
        child: CustomPaint(
          size: Size(box.maxWidth, box.maxHeight),
          painter: _PresetPainter(items, selectedIndex, scale),
        ),
      );
    });
  }

  int? _hitTest(Offset worldM) {
    for (var i = items.length - 1; i >= 0; i--) {
      final p = items[i];
      final (hw, hh) = _presetHalfExtentsM(p);
      if ((worldM.dx - p.x).abs() <= hw && (worldM.dy - p.y).abs() <= hh) {
        return i;
      }
    }
    return null;
  }
}

class _PresetPainter extends CustomPainter {
  _PresetPainter(this.items, this.selectedIndex, this.scale);

  final List<PresetObject> items;
  final int? selectedIndex;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFBEE7F5));
    final bounds = Rect.fromLTRB(kFieldMinX * scale, kFieldMinY * scale,
        kFieldMaxX * scale, kFieldMaxY * scale);
    canvas.drawRect(
      bounds,
      Paint()
        ..color = const Color(0x55263238)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < items.length; i++) {
      final p = items[i];
      final (hw, hh) = _presetHalfExtentsM(p);
      final rect = Rect.fromCenter(
        center: Offset(p.x * scale, p.y * scale),
        width: hw * 2 * scale,
        height: hh * 2 * scale,
      );
      final selected = i == selectedIndex;
      canvas.drawRect(
        rect,
        Paint()
          ..color =
              selected ? const Color(0xFFFFC107) : const Color(0xFFA1887F),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFF263238)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 3 : 1.5,
      );
    }
  }

  // Cheap and always-correct beats diffing a mutated-in-place list for a
  // handful of preset objects in a debug-only tool.
  @override
  bool shouldRepaint(covariant _PresetPainter oldDelegate) => true;
}

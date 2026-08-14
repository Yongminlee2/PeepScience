// flame/game.dart also exports its own unrelated `Route` (RouterComponent's
// in-game navigation, never used here) - hide it so flutter/material.dart's
// Navigator `Route` (used by fadeRoute below) resolves unambiguously.
import 'package:flame/game.dart' hide Route;
import 'package:flutter/material.dart';

import '../game/piyak_game.dart';
import '../services/progress.dart';
import '../services/stage_loader.dart';
import '../sim/registry.dart';
import '../sim/stage_data.dart';

/// ~250ms fade-in transition for entering [GameScreen] (owner-approved
/// polish pass - a flat MaterialPageRoute cut straight into the game read as
/// jarring). Pop/back behavior is whatever PageRouteBuilder's own default
/// is - unchanged from a plain push/pushReplacement. Shared by
/// home_screen.dart's initial stage-open and this file's own next-stage
/// advance ([_GameScreenState._handleNext]) so both entry points feel the
/// same instead of duplicating the transition twice.
Route<T> fadeRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          builder(context),
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );

/// Hosts one stage's [PiyakGame]. Reached either with an already-loaded
/// [initialStage] (home screen validates the load before ever navigating
/// here - see home_screen.dart's `_openStage`) or with just a [stageId],
/// which this screen loads itself via [loader] (the path taken when
/// [onNextRequested] advances to the following stage - nothing upstream has
/// pre-loaded that one).
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.stageId,
    this.initialStage,
    this.loader,
    this.onProgressChanged,
  });

  final String stageId;
  final StageData? initialStage;

  /// Defaults to [StageLoader.load] when null (see `_GameScreenState._future`)
  /// - a plain nullable field, rather than resolving the default in an
  /// initializer list, so this constructor stays const-constructible.
  final Future<StageData> Function(String id)? loader;

  /// Notified right after every markCleared. Home screen wires this to its
  /// own progress refresh so the grid picks up progress made across a whole
  /// chain of stage-to-stage advances, not just the first: `pushReplacement`
  /// completes the *original* pushed route immediately (on the very first
  /// advance), so relying solely on `await Navigator.push(...)` resolving
  /// would miss every clear after that one - see task-11-report.md.
  final VoidCallback? onProgressChanged;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<StageData> _future = widget.initialStage != null
      ? Future.value(widget.initialStage)
      : (widget.loader ?? StageLoader.load)(widget.stageId);

  PiyakGame? _game;

  void _handleCleared(String id) async {
    final p = await ProgressStore.init();
    await p.markCleared(id);
    widget.onProgressChanged?.call();
  }

  void _handleNext() {
    final i = stageOrder.indexOf(widget.stageId);
    final hasNext = i != -1 && i + 1 < stageOrder.length;
    if (!hasNext) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).pushReplacement(fadeRoute((_) => GameScreen(
          stageId: stageOrder[i + 1],
          loader: widget.loader,
          onProgressChanged: widget.onProgressChanged,
        )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<StageData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            // ⚠ 파손: stage JSON을 못 읽거나 파싱에 실패한 경우 (예: task 13
            // 이전이라 assets/stages/*.json 자체가 아직 없는 경우). 아이콘만
            // 쓰는 이유는 hud.dart의 GoalBadge와 동일 - 언어와 무관하게 즉시
            // 읽혀야 하는 상태 표시.
            return SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚠', style: TextStyle(fontSize: 72)),
                    const SizedBox(height: 24),
                    IconButton(
                      iconSize: 48,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            );
          }
          final game = _game ??= PiyakGame(snap.data!)
            ..onCleared = _handleCleared
            ..onNextRequested = _handleNext;
          return GameWidget(game: game);
        },
      ),
    );
  }
}

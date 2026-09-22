import 'dart:async';

// flame/game.dart also exports its own unrelated `Route` (RouterComponent's
// in-game navigation, never used here) - hide it so flutter/material.dart's
// Navigator `Route` (used by fadeRoute below) resolves unambiguously.
import 'package:flame/game.dart' hide Route;
import 'package:flutter/material.dart';

import '../game/piyak_game.dart';
import '../services/ads.dart';
import '../services/progress.dart';
import '../services/stage_loader.dart';
import '../sim/registry.dart';
import '../sim/stage_data.dart';
import 'strings.dart';
import 'theme.dart';
import 'tutorial_overlay.dart';

/// ~250ms fade-in transition for entering [GameScreen] (owner-approved
/// polish pass - a flat MaterialPageRoute cut straight into the game read as
/// jarring). Pop/back behavior is whatever PageRouteBuilder's own default
/// is - unchanged from a plain push/pushReplacement. Shared by
/// home_screen.dart's initial stage-open and this file's own next-stage
/// advance ([_GameScreenState._handleNext]) so both entry points feel the
/// same instead of duplicating the transition twice.
Route<T> fadeRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
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

  /// Notified right after progress is saved. Home screen wires this to its
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
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstVisitTutorial());
  }

  Future<void> _loadFirstVisitTutorial() async {
    if (stageOrder.isEmpty || widget.stageId != stageOrder.first) return;
    final progress = await ProgressStore.init();
    final seen = await progress.tutorialSeen();
    if (mounted && !seen) setState(() => _showTutorial = true);
  }

  void _openTutorial() {
    setState(() => _showTutorial = true);
  }

  void _finishTutorial() {
    setState(() => _showTutorial = false);
    _game?.triggerGoalPulse();
    unawaited(_rememberTutorial());
  }

  Future<void> _rememberTutorial() async {
    final progress = await ProgressStore.init();
    await progress.markTutorialSeen();
  }

  void _handleCleared(String id, int stars) async {
    final p = await ProgressStore.init();
    // Save the score before the clear flag. ProgressStore backfills legacy
    // cleared stages as 3-star clears, so reversing this order would make a
    // brand-new 1/2-star result look like legacy data.
    await p.markStars(id, stars);
    await p.markCleared(id);
    widget.onProgressChanged?.call();
  }

  Future<void> _handleNext() async {
    // 광고는 판이 바뀌는 이 순간에만 낀다. 받아 둔 광고가 없거나 차례가
    // 아니면 곧바로 돌아오므로 다음 판이 늦게 열리지 않는다.
    await Ads.maybeShowOnStageAdvance();
    if (!mounted) return;
    final i = stageOrder.indexOf(widget.stageId);
    final hasNext = i != -1 && i + 1 < stageOrder.length;
    if (!hasNext) {
      // 한 판씩 pushReplacement로 갈아끼우므로 게임 route는 늘 하나다.
      // 한 번 pop하면 월드 목록으로 돌아간다(메인 화면까지 가면 안 된다).
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      fadeRoute(
        (_) => GameScreen(
          stageId: stageOrder[i + 1],
          loader: widget.loader,
          onProgressChanged: widget.onProgressChanged,
        ),
      ),
    );
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
          return Stack(
            fit: StackFit.expand,
            children: [
              GameWidget(game: game),
              // 하단 정렬: 이 두 버튼은 게임 캔버스 위에 떠 있는 Flutter
              // 위젯이라 어디에 놓든 놓인 자리의 필드를 가린다. 화면 아래
              // 150px 띠는 트레이 바가 이미 차지해 어떤 스테이지도 쓰지
              // 않는 유일한 공간이라, 여기 두면 부품·공을 절대 덮지 않는다.
              // (위쪽에 두었을 때 시작 공이 통째로 가려지는 판이 있었다.)
              Positioned(
                bottom: 14,
                right: 16,
                child: SafeArea(
                  child: _RoundHudButton(
                    semanticLabel: S.t('home'),
                    tooltip: S.t('home'),
                    icon: Icons.home_rounded,
                    fillColor: kCandyCream,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                right: 82,
                child: SafeArea(
                  child: _RoundHudButton(
                    key: const ValueKey('tutorial_help'),
                    semanticLabel: S.t('tutorialHelp'),
                    tooltip: S.t('tutorialHelp'),
                    icon: Icons.lightbulb_rounded,
                    fillColor: kCandyGold,
                    onPressed: _openTutorial,
                  ),
                ),
              ),
              if (_showTutorial)
                TutorialOverlay(
                  goalType: game.stage.goal.type,
                  onFinished: _finishTutorial,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RoundHudButton extends StatelessWidget {
  const _RoundHudButton({
    super.key,
    required this.semanticLabel,
    required this.tooltip,
    required this.icon,
    required this.fillColor,
    required this.onPressed,
  });

  final String semanticLabel;
  final String tooltip;
  final IconData icon;
  final Color fillColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: kChocolateOutline, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        color: kChocolateOutline,
        onPressed: onPressed,
      ),
    ),
  );
}

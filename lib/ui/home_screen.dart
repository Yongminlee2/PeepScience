import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../editor/editor_screen.dart';
import '../services/progress.dart';
import '../services/stage_loader.dart';
import '../sim/stage_data.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'theme.dart';

const int _stagesPerWorld = 10;
const int _worldCount = 4;

String _stageId(int world, int index) =>
    'w${world}_s${index.toString().padLeft(2, '0')}';

/// App root screen: 4 horizontally-scrolling world cards, each holding its
/// own 10-stage grid (✓ cleared / number unlocked / lock locked / ⚠ broken).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.stageLoader = StageLoader.load});

  /// Injectable for tests; production default reads real stage assets via
  /// [StageLoader.load]. A stage is loaded lazily - only the instant its
  /// cell is tapped - never eagerly for all 40 cells on every home render:
  /// assets/stages/*.json don't exist until task 13, so eager probing would
  /// be both wasteful and, today, universally-failing. A cell that fails to
  /// load on tap flips to the ⚠ broken state instead of navigating - see
  /// [_openStage].
  final Future<StageData> Function(String id) stageLoader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProgressStore? _progress;
  Set<String> _cleared = {};
  final Set<String> _broken = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final p = await ProgressStore.init();
      final c = await p.cleared();
      if (!mounted) return;
      setState(() {
        _progress = p;
        _cleared = c;
      });
    } catch (_) {
      // Boot/home must never crash on a progress-store failure - the grid
      // just stays fail-closed (nothing beyond the built-in defaults reads
      // as unlocked) instead of taking the app down with it.
    }
  }

  bool _isUnlocked(String id) =>
      _cleared.contains(id) || (_progress?.isUnlocked(id, _cleared) ?? false);

  Future<void> _openStage(String id) async {
    if (!_isUnlocked(id)) return;
    try {
      final data = await widget.stageLoader(id);
      if (!mounted) return;
      await Navigator.of(context).push(fadeRoute((_) => GameScreen(
            stageId: id,
            initialStage: data,
            onProgressChanged: _refresh,
          )));
      _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _broken.add(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listens to AppLang directly rather than relying on some ancestor
    // rebuild to cascade down: home is the Navigator's *initial* route, and
    // `MaterialApp(home: const HomeScreen())` is a canonicalized const
    // instance - Flutter's element diffing bails out of rebuilding a child
    // whose incoming widget is `identical` to the one already there, so an
    // ancestor-level rebuild alone never reaches back into an
    // already-built const route (confirmed by nav_test.dart's language
    // test failing without this). Subscribing here works regardless of
    // that, and regardless of whether home is the visible/top route.
    return ValueListenableBuilder<String>(
      valueListenable: AppLang(),
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Text(S.t('appTitle')),
          actions: [
            // Debug-only stage editor entry - kDebugMode is a compile-time
            // constant, so this whole branch (and EditorScreen along with
            // it) is dead-code-eliminated from release builds, matching the
            // brief's "릴리스 빌드에는 라우트 자체가 없음" requirement.
            if (kDebugMode)
              IconButton(
                icon: const Icon(Icons.build),
                tooltip: 'Stage Editor',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EditorScreen(),
                )),
              ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              )),
            ),
          ],
        ),
        body: ListView(
          scrollDirection: Axis.horizontal,
          padding: scrollPadding(context),
          children: List.generate(
            _worldCount,
            (i) => _WorldCard(
              world: i + 1,
              cleared: _cleared,
              broken: _broken,
              isUnlocked: _isUnlocked,
              onTapStage: _openStage,
            ),
          ),
        ),
      ),
    );
  }
}

enum _CellState { cleared, unlocked, locked, broken }

class _WorldCard extends StatelessWidget {
  const _WorldCard({
    required this.world,
    required this.cleared,
    required this.broken,
    required this.isUnlocked,
    required this.onTapStage,
  });

  final int world;
  final Set<String> cleared;
  final Set<String> broken;
  final bool Function(String id) isUnlocked;
  final void Function(String id) onTapStage;

  static const double _width = 420;
  static const double _headerHeight = 90;

  int get _clearedCount => List.generate(
        _stagesPerWorld,
        (i) => _stageId(world, i + 1),
      ).where(cleared.contains).length;

  @override
  Widget build(BuildContext context) {
    // errorBuilder 전용 폴백 색(월드별 고유색 유지) - 카드 바탕 자체는 이제
    // 캔디 크림(kCandyCream)으로 고정되므로 밝기 기반 fg 텍스트색 계산은
    // 더 이상 필요 없다.
    final bgFallback = worldCardColors[world - 1];
    return Container(
      width: _width,
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kCandyCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kChocolateOutline, width: 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 월드 배경 아트를 카드 헤더 썸네일로(오너 피드백: "디자인이
          // 조잡하다" - 이미 번들된 bg 에셋을 홈 화면은 안 쓰고 있었다).
          // 에셋이 없거나 로드에 실패하면 기존처럼 월드 고유 플랫 컬러로
          // 조용히 대체된다.
          SizedBox(
            height: _headerHeight,
            width: double.infinity,
            child: Image.asset(
              'assets/images/bg/world$world.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: bgFallback),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        S.t('world$world'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: kChocolateOutline,
                        ),
                      ),
                      _ProgressChip(cleared: _clearedCount, total: _stagesPerWorld),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: _stagesPerWorld,
                      itemBuilder: (context, i) {
                        final index = i + 1;
                        final id = _stageId(world, index);
                        final state = broken.contains(id)
                            ? _CellState.broken
                            : cleared.contains(id)
                                ? _CellState.cleared
                                : isUnlocked(id)
                                    ? _CellState.unlocked
                                    : _CellState.locked;
                        return _StageCell(
                          key: ValueKey('cell_$id'),
                          index: index,
                          state: state,
                          onTap: () => onTapStage(id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "n/10" 진행도 칩 - 클리어 개수를 클리어 세트에서 그대로 유도(별도
/// 저장/캐시 없음). [_WorldCard]의 헤더 Row 안, 월드 제목 옆에 표시.
class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.cleared, required this.total});

  final int cleared;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kCandyGold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kChocolateOutline, width: 2),
      ),
      child: Text(
        '$cleared/$total',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: kChocolateOutline,
        ),
      ),
    );
  }
}

class _StageCell extends StatelessWidget {
  const _StageCell({
    super.key,
    required this.index,
    required this.state,
    required this.onTap,
  });

  final int index;
  final _CellState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tappable =
        state == _CellState.cleared || state == _CellState.unlocked;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tappable ? onTap : null,
        child: Center(child: _content()),
      ),
    );
  }

  Widget _content() => switch (state) {
        _CellState.cleared => const Icon(Icons.check, color: Colors.green),
        _CellState.unlocked =>
          Text('$index', style: const TextStyle(fontWeight: FontWeight.bold)),
        _CellState.locked =>
          const Icon(Icons.lock, size: 16, color: Colors.grey),
        _CellState.broken => const Text('⚠'),
      };
}

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../editor/editor_screen.dart';
import '../services/progress.dart';
import '../services/stage_loader.dart';
import '../sim/stage_data.dart';
import 'ad_banner.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'theme.dart';

const int _stagesPerWorld = 20;
const int _stagesPerPage = 10;
const int _worldCount = 5;

/// Device-QA hook. It is false (and tree-shaken) in every ordinary build;
/// a temporary release build can opt in with
/// `--dart-define=PIYAK_QA_UNLOCK_ALL=true` so late-stage interactions are
/// testable on hardware without mutating a tester's saved progress.
const bool _qaUnlockAll = bool.fromEnvironment('PIYAK_QA_UNLOCK_ALL');

String _stageId(int world, int index) =>
    'w${world}_s${index.toString().padLeft(2, '0')}';

/// App root screen: 4 horizontally-scrolling world cards, each holding its
/// own paged 20-stage grid (✓ cleared / number unlocked / lock locked / ⚠
/// broken).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.stageLoader = StageLoader.load});

  /// Injectable for tests; production default reads real stage assets via
  /// [StageLoader.load]. A stage is loaded lazily - only the instant its
  /// cell is tapped - never eagerly for all 80 cells on every home render:
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
  Map<String, int> _stars = {};
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
      final stars = await p.stars();
      if (!mounted) return;
      setState(() {
        _progress = p;
        _cleared = c;
        _stars = stars;
      });
    } catch (_) {
      // Boot/home must never crash on a progress-store failure - the grid
      // just stays fail-closed (nothing beyond the built-in defaults reads
      // as unlocked) instead of taking the app down with it.
    }
  }

  bool _isUnlocked(String id) =>
      _qaUnlockAll ||
      _cleared.contains(id) ||
      (_progress?.isUnlocked(id, _cleared) ?? false);

  Future<void> _openStage(String id) async {
    if (!_isUnlocked(id)) return;
    try {
      final data = await widget.stageLoader(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        fadeRoute(
          (_) => GameScreen(
            stageId: id,
            initialStage: data,
            onProgressChanged: _refresh,
          ),
        ),
      );
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
          toolbarHeight: 72,
          titleSpacing: 20,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'store/art/icon_6.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    S.t('appTitle'),
                    style: const TextStyle(
                      color: kChocolateOutline,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    S.t('homeTagline'),
                    style: TextStyle(
                      color: kChocolateOutline.withAlpha(170),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            // Debug-only stage editor entry - kDebugMode is a compile-time
            // constant, so this whole branch (and EditorScreen along with
            // it) is dead-code-eliminated from release builds, matching the
            // brief's "릴리스 빌드에는 라우트 자체가 없음" requirement.
            if (kDebugMode)
              IconButton(
                icon: const Icon(Icons.build),
                tooltip: 'Stage Editor',
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const EditorScreen())),
              ),
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(right: 18),
              decoration: BoxDecoration(
                color: kCandyCream,
                shape: BoxShape.circle,
                border: Border.all(color: kChocolateOutline, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.settings_rounded),
                color: kChocolateOutline,
                tooltip: S.t('settings'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ),
          ],
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kHomeCanvasTop, kHomeCanvasBottom],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: scrollPadding(context),
                  children: List.generate(
                    _worldCount,
                    (i) => _WorldCard(
                      world: i + 1,
                      cleared: _cleared,
                      stars: _stars,
                      broken: _broken,
                      isUnlocked: _isUnlocked,
                      onTapStage: _openStage,
                    ),
                  ),
                ),
              ),
              // 띠 광고는 카드 아래 여백에만 놓는다. 광고가 없으면 높이 0이라
              // 홈 화면이 예전과 똑같이 보인다.
              const AdBanner(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CellState { cleared, unlocked, locked, broken }

class _WorldCard extends StatefulWidget {
  const _WorldCard({
    required this.world,
    required this.cleared,
    required this.stars,
    required this.broken,
    required this.isUnlocked,
    required this.onTapStage,
  });

  final int world;
  final Set<String> cleared;
  final Map<String, int> stars;
  final Set<String> broken;
  final bool Function(String id) isUnlocked;
  final void Function(String id) onTapStage;

  @override
  State<_WorldCard> createState() => _WorldCardState();
}

class _WorldCardState extends State<_WorldCard> {
  static const double _width = 392;
  static const double _headerHeight = 76;
  int _page = 0;

  int get _clearedCount => List.generate(
    _stagesPerWorld,
    (i) => _stageId(widget.world, i + 1),
  ).where(widget.cleared.contains).length;

  int get _starCount => List.generate(
    _stagesPerWorld,
    (i) => widget.stars[_stageId(widget.world, i + 1)] ?? 0,
  ).fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    // errorBuilder 전용 폴백 색(월드별 고유색 유지) - 카드 바탕 자체는 이제
    // 캔디 크림(kCandyCream)으로 고정되므로 밝기 기반 fg 텍스트색 계산은
    // 더 이상 필요 없다.
    final world = widget.world;
    final bgFallback = worldCardColors[world - 1];
    return Container(
      width: _width,
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kCandyCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kChocolateOutline, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
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
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 제목 칸은 별을 모을수록 좁아진다(진행 칩이 넓어지므로).
                      // 그래서 자르지 않고 줄여서 넣는다 - 잘린 이름은 어느
                      // 월드인지 알 수 없게 만드는데, 긴 이름을 쓰는 언어가
                      // 여럿이라(독일어 Kinderzimmer, 태국어 등) 번역을
                      // 짧게 다듬는 것만으로는 다음 언어에서 또 터진다.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              S.t('world$world'),
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: kChocolateOutline,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StagePageSwitcher(
                        world: world,
                        page: _page,
                        onChanged: (page) => setState(() => _page = page),
                      ),
                      const SizedBox(width: 8),
                      _ProgressChip(
                        cleared: _clearedCount,
                        total: _stagesPerWorld,
                        stars: _starCount,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: GridView.builder(
                        key: ValueKey('stage_grid_w${world}_p$_page'),
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                        itemCount: _stagesPerPage,
                        itemBuilder: (context, i) {
                          final index = _page * _stagesPerPage + i + 1;
                          final id = _stageId(world, index);
                          final state = widget.broken.contains(id)
                              ? _CellState.broken
                              : widget.cleared.contains(id)
                              ? _CellState.cleared
                              : widget.isUnlocked(id)
                              ? _CellState.unlocked
                              : _CellState.locked;
                          return _StageCell(
                            key: ValueKey('cell_$id'),
                            index: index,
                            state: state,
                            stars: widget.stars[id] ?? 0,
                            onTap: () => widget.onTapStage(id),
                          );
                        },
                      ),
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

/// Keeps the proven 5x2 stage-cell size on short landscape phones while
/// exposing the mastery half of the world. The arrows live in the existing
/// header row, so pagination never steals vertical room from the tap grid.
class _StagePageSwitcher extends StatelessWidget {
  const _StagePageSwitcher({
    required this.world,
    required this.page,
    required this.onChanged,
  });

  final int world;
  final int page;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: kChocolateOutline, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(
            key: ValueKey('stage_page_prev_w$world'),
            icon: Icons.chevron_left_rounded,
            targetPage: page - 1,
            enabled: page > 0,
          ),
          SizedBox(
            width: 44,
            child: Text(
              page == 0 ? '1–10' : '11–20',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kChocolateOutline,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _arrow(
            key: ValueKey('stage_page_next_w$world'),
            icon: Icons.chevron_right_rounded,
            targetPage: page + 1,
            enabled: page < 1,
          ),
        ],
      ),
    );
  }

  Widget _arrow({
    required Key key,
    required IconData icon,
    required int targetPage,
    required bool enabled,
  }) {
    return IconButton(
      key: key,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20),
      color: kChocolateOutline,
      disabledColor: kChocolateOutline.withAlpha(45),
      onPressed: enabled ? () => onChanged(targetPage) : null,
    );
  }
}

/// "n/20" 진행도 칩 - 클리어 개수를 클리어 세트에서 그대로 유도(별도
/// 저장/캐시 없음). [_WorldCard]의 헤더 Row 안, 월드 제목 옆에 표시.
class _ProgressChip extends StatelessWidget {
  const _ProgressChip({
    required this.cleared,
    required this.total,
    required this.stars,
  });

  final int cleared;
  final int total;
  final int stars;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kCandyGold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kChocolateOutline, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$cleared/$total',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: kChocolateOutline,
            ),
          ),
          if (stars > 0) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFF8F00)),
            Text(
              '$stars',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: kChocolateOutline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageCell extends StatelessWidget {
  const _StageCell({
    super.key,
    required this.index,
    required this.state,
    required this.stars,
    required this.onTap,
  });

  final int index;
  final _CellState state;
  final int stars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tappable =
        state == _CellState.cleared || state == _CellState.unlocked;
    final fill = switch (state) {
      _CellState.cleared => const Color(0xFFE6F5DD),
      _CellState.unlocked => const Color(0xFFFFF0B8),
      _CellState.locked => const Color(0xFFF1ECE7),
      _CellState.broken => const Color(0xFFFFE0D8),
    };
    final border = switch (state) {
      _CellState.cleared => const Color(0xFF66BB6A),
      _CellState.unlocked => kCandyGold,
      _CellState.locked => kChocolateOutline.withAlpha(36),
      _CellState.broken => const Color(0xFFE85D45),
    };
    return Semantics(
      button: tappable,
      enabled: tappable,
      label: '${S.t('playStage')} $index',
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: border,
            width: state == _CellState.unlocked ? 3 : 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tappable ? onTap : null,
          child: Center(child: _content()),
        ),
      ),
    );
  }

  Widget _content() => switch (state) {
    _CellState.cleared => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => Icon(
          i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
          color: i < stars ? const Color(0xFFFFB300) : const Color(0xFF8FA88B),
          size: 17,
        ),
      ),
    ),
    _CellState.unlocked => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$index',
          style: const TextStyle(
            color: kChocolateOutline,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(width: 2),
        const Icon(
          Icons.play_arrow_rounded,
          color: kChocolateOutline,
          size: 22,
        ),
      ],
    ),
    _CellState.locked => Icon(
      Icons.lock_rounded,
      size: 20,
      color: kChocolateOutline.withAlpha(105),
    ),
    _CellState.broken => const Text('⚠'),
  };
}

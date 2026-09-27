import 'package:flutter/material.dart';

import '../services/app_update.dart';
import '../services/progress.dart';
import '../services/sound.dart';
import '../sim/catalog.dart';
import '../sim/registry.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'theme.dart';
import 'tutorial_overlay.dart';

/// 앱을 열면 가장 먼저 나오는 메인 화면.
///
/// 가로 화면 왼쪽에 제목 카드(병아리·별 진행도), 오른쪽에 메뉴를 둔다. 뒤에는
/// 지금 진행 중인 월드의 배경 그림을 깐다 - 월드를 넘어가면 메인 화면도
/// 바뀌어서 "여기까지 왔다"가 보인다.
///
/// 제목을 일곱 번 두드리면 개발자 모드(모든 판 열기)가 켜지고 꺼진다.
/// 기기 안에만 저장되므로 만든 사람 폰에서만 쓴다(삐약푸쉬와 같은 방식).
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  int _stars = 0;
  String _next = stageOrder.first;
  bool _devUnlock = false;

  static final int _maxStars = stageOrder.length * 3;

  @override
  void initState() {
    super.initState();
    _refresh();
    // 첫 화면이 뜬 뒤에 스토어 새 버전을 확인한다(화면이 붙기 전에는 플레이의
    // 업데이트 화면을 띄울 수 없다).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => AppUpdate.checkOnLaunch(),
    );
  }

  Future<void> _refresh() async {
    try {
      final p = await ProgressStore.init();
      final stars = await p.stars();
      final cleared = await p.cleared();
      if (!mounted) return;
      setState(() {
        _stars = stars.values.fold(0, (a, b) => a + b);
        _next = p.nextStage(cleared);
        _devUnlock = p.devUnlockAll();
      });
    } catch (_) {
      // 진행 기록을 못 읽어도 메인 화면은 떠야 한다.
    }
  }

  int get _world => int.tryParse(_next.substring(1, 2)) ?? 1;

  Future<void> _go(Widget page) async {
    Sound.play(Sfx.tap);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _refresh();
  }

  void _openGuide() {
    Sound.play(Sfx.tap);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (context, _, _) => TutorialOverlay(
          goalType: GoalType.ballInBasket,
          onFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _toggleDev() async {
    final p = await ProgressStore.init();
    final on = !p.devUnlockAll();
    await p.setDevUnlockAll(on);
    if (!mounted) return;
    setState(() => _devUnlock = on);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(on ? '개발자 모드 켜짐 — 모든 판이 열려요' : '개발자 모드 꺼짐'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 설정에서 언어를 바꾸면 이 화면 글자도 같이 바뀌어야 한다.
    return ValueListenableBuilder<String>(
      valueListenable: AppLang(),
      builder: (context, _, _) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/bg/world$_world.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: kHomeCanvasTop),
            ),
            // 그림 위 글자가 읽히도록 밝게 한 겹 덮는다.
            const ColoredBox(color: Color(0x66FFFAF4)),
            SafeArea(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TitleCard(
                          stars: _stars,
                          maxStars: _maxStars,
                          devUnlock: _devUnlock,
                          onSecret: _toggleDev,
                        ),
                        const SizedBox(width: 36),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MenuButton(
                              key: const ValueKey('title_play'),
                              icon: Icons.play_arrow_rounded,
                              label: S.t('play'),
                              primary: true,
                              onPressed: () => _go(const HomeScreen()),
                            ),
                            _MenuButton(
                              key: const ValueKey('title_continue'),
                              icon: Icons.fast_forward_rounded,
                              label: S.t('continue'),
                              onPressed: () =>
                                  _go(HomeScreen(openStageOnStart: _next)),
                            ),
                            _MenuButton(
                              key: const ValueKey('title_guide'),
                              icon: Icons.lightbulb_rounded,
                              label: S.t('tutorialHelp'),
                              onPressed: _openGuide,
                            ),
                            _MenuButton(
                              key: const ValueKey('title_settings'),
                              icon: Icons.settings_rounded,
                              label: S.t('settings'),
                              onPressed: () => _go(const SettingsScreen()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 제목·병아리·별 진행도가 든 흰 카드.
class _TitleCard extends StatelessWidget {
  const _TitleCard({
    required this.stars,
    required this.maxStars,
    required this.devUnlock,
    required this.onSecret,
  });

  final int stars;
  final int maxStars;
  final bool devUnlock;
  final VoidCallback onSecret;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kChocolateOutline, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x335D4037), offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SecretTap(
            onTriggered: onSecret,
            child: Text(
              S.t('appTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: kChocolateOutline,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.t('homeTagline'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          const _BouncyChick(),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: maxStars == 0 ? 0 : stars / maxStars,
              minHeight: 12,
              backgroundColor: kCandyCream,
              valueColor: const AlwaysStoppedAnimation(kCandyGold),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: kCandyGold, size: 22),
              Text(
                ' $stars / $maxStars',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kChocolateOutline,
                ),
              ),
            ],
          ),
          if (devUnlock) ...[
            const SizedBox(height: 8),
            const Text(
              '🔓 개발자 모드 · 모든 판 열림',
              style: TextStyle(fontSize: 13, color: Color(0xFF8D6E63)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 누르면 통통 튀며 삐약 소리를 내는 병아리(앱 아이콘 그림).
class _BouncyChick extends StatefulWidget {
  const _BouncyChick();

  @override
  State<_BouncyChick> createState() => _BouncyChickState();
}

class _BouncyChickState extends State<_BouncyChick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _poke() {
    Sound.play(Sfx.boing);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('title_chick'),
      onTap: _poke,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // 한 번 폴짝 뛰었다가 살짝 찌그러지며 내려앉는다.
          final t = Curves.easeOut.transform(_c.value);
          final jump = -26 * (1 - (2 * t - 1) * (2 * t - 1));
          return Transform.translate(offset: Offset(0, jump), child: child);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            'store/art/icon_6.png',
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

/// 메뉴 버튼. 누르는 동안 살짝 줄어든다.
class _MenuButton extends StatefulWidget {
  const _MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(30)),
              boxShadow: [
                BoxShadow(color: Color(0x335D4037), offset: Offset(0, 4)),
              ],
            ),
            child: FilledButton.icon(
              onPressed: widget.onPressed,
              icon: Icon(widget.icon, size: 28),
              label: Text(widget.label),
              style: FilledButton.styleFrom(
                backgroundColor: widget.primary ? kCandyGold : Colors.white,
                foregroundColor: kChocolateOutline,
                minimumSize: const Size(280, 60),
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                shape: const StadiumBorder(
                  side: BorderSide(color: kChocolateOutline, width: 3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 일곱 번 연달아 두드리면 [onTriggered]. 2초 넘게 쉬면 처음부터 다시 센다.
class _SecretTap extends StatefulWidget {
  const _SecretTap({required this.onTriggered, required this.child});

  final VoidCallback onTriggered;
  final Widget child;

  @override
  State<_SecretTap> createState() => _SecretTapState();
}

class _SecretTapState extends State<_SecretTap> {
  static const _needed = 7;
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _tap() {
    final now = DateTime.now();
    _taps = now.difference(_last) > const Duration(seconds: 2) ? 1 : _taps + 1;
    _last = now;
    if (_taps < _needed) return;
    _taps = 0;
    widget.onTriggered();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('title_secret'),
    behavior: HitTestBehavior.opaque,
    onTap: _tap,
    child: widget.child,
  );
}

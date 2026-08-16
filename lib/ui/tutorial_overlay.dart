import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sim/catalog.dart';
import 'strings.dart';
import 'theme.dart';

/// A short, replayable first-experiment guide.
///
/// The game itself stays visible behind the dimmed layer so the instructions
/// always point at the real interface. Every illustrated object is one of the
/// shipped game sprites; Material icons are reserved for gestures/actions.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.goalType,
    required this.onFinished,
  });

  final GoalType goalType;
  final VoidCallback onFinished;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  static const _pageCount = 4;

  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.97,
    end: 1.03,
  ).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeInOut));

  int _page = 0;

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      widget.onFinished();
      return;
    }
    setState(() => _page += 1);
  }

  void _back() {
    if (_page > 0) setState(() => _page -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      S.t('tutorialGoalTitle'),
      S.t('tutorialDragTitle'),
      S.t('tutorialRotateTitle'),
      S.t('tutorialRunTitle'),
    ];
    final bodies = [
      S.t('tutorialGoalBody'),
      S.t('tutorialDragBody'),
      S.t('tutorialRotateBody'),
      S.t('tutorialRunBody'),
    ];

    return Material(
      key: const ValueKey('tutorial_overlay'),
      color: const Color(0xA6000000),
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(720.0, constraints.maxWidth);
            final height = math.min(326.0, constraints.maxHeight);
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kCandyCream,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: kChocolateOutline, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 22,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
                    child: Column(
                      children: [
                        _Header(page: _page, pageCount: _pageCount),
                        const SizedBox(height: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.08, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: _TutorialPage(
                              key: ValueKey(_page),
                              page: _page,
                              title: titles[_page],
                              body: bodies[_page],
                              scale: _scale,
                              goalType: widget.goalType,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Footer(
                          page: _page,
                          pageCount: _pageCount,
                          onBack: _back,
                          onNext: _next,
                          onSkip: widget.onFinished,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.page, required this.pageCount});

  final int page;
  final int pageCount;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.asset(
          'store/art/icon_6.png',
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.t('tutorialTitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kChocolateOutline,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              S.t('tutorialSubtitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xCC6D4C43),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kCandyGold,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kChocolateOutline, width: 2),
        ),
        child: Text(
          '${page + 1}/$pageCount',
          style: const TextStyle(
            color: kChocolateOutline,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _TutorialPage extends StatelessWidget {
  const _TutorialPage({
    super.key,
    required this.page,
    required this.title,
    required this.body,
    required this.scale,
    required this.goalType,
  });

  final int page;
  final String title;
  final String body;
  final Animation<double> scale;
  final GoalType goalType;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 240,
        child: Center(
          child: ScaleTransition(
            scale: scale,
            child: _PageVisual(page: page, goalType: goalType),
          ),
        ),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kChocolateOutline,
                fontSize: 23,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xDD5D4037),
                fontSize: 15,
                height: 1.32,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PageVisual extends StatelessWidget {
  const _PageVisual({required this.page, required this.goalType});

  final int page;
  final GoalType goalType;

  @override
  Widget build(BuildContext context) => switch (page) {
    0 => _goalVisual(),
    1 => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _part('plank.png', 190, 36),
        const Positioned(
          right: 5,
          bottom: -24,
          child: _ActionBadge(icon: Icons.touch_app_rounded),
        ),
      ],
    ),
    2 => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Transform.rotate(angle: -0.26, child: _part('plank.png', 190, 36)),
        const Positioned(
          right: 8,
          top: -24,
          child: _ActionBadge(icon: Icons.rotate_right_rounded),
        ),
      ],
    ),
    _ => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PlayBadge(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward_rounded,
            color: kChocolateOutline,
            size: 34,
          ),
        ),
        _part('collectible_star.png', 72, 72),
      ],
    ),
  };

  Widget _goalVisual() {
    final (source, sourceSize, target, targetSize) = switch (goalType) {
      GoalType.ballInBasket => (
        'rubber_ball.png',
        const Size(68, 68),
        'basket.png',
        const Size(96, 72),
      ),
      GoalType.pressButton => (
        'metal_ball.png',
        const Size(68, 68),
        'button.png',
        const Size(104, 48),
      ),
      GoalType.popBalloons => (
        'balloon.png',
        const Size(74, 74),
        'tack.png',
        const Size(58, 58),
      ),
      GoalType.toppleDominoes => (
        'rubber_ball.png',
        const Size(68, 68),
        'domino.png',
        const Size(38, 92),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _part(source, sourceSize.width, sourceSize.height),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward_rounded,
            color: kChocolateOutline,
            size: 34,
          ),
        ),
        _part(target, targetSize.width, targetSize.height),
      ],
    );
  }

  Widget _part(String file, double width, double height) => Image.asset(
    'assets/images/parts/$file',
    width: width,
    height: height,
    fit: BoxFit.contain,
  );
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: kCandyGold,
      shape: BoxShape.circle,
      border: Border.all(color: kChocolateOutline, width: 2.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Icon(icon, color: kChocolateOutline, size: 29),
  );
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: const Color(0xFF66BB6A),
      shape: BoxShape.circle,
      border: Border.all(color: kChocolateOutline, width: 3),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: const Icon(Icons.play_arrow_rounded, color: kCandyCream, size: 48),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.page,
    required this.pageCount,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final int page;
  final int pageCount;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      TextButton(
        key: const ValueKey('tutorial_skip'),
        onPressed: onSkip,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF7A625B),
          minimumSize: const Size(92, 48),
        ),
        child: Text(
          S.t('tutorialSkip'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      const Spacer(),
      if (page > 0) ...[
        OutlinedButton.icon(
          key: const ValueKey('tutorial_back'),
          onPressed: onBack,
          style: OutlinedButton.styleFrom(
            foregroundColor: kChocolateOutline,
            side: const BorderSide(color: kChocolateOutline, width: 2),
            minimumSize: const Size(96, 48),
          ),
          icon: const Icon(Icons.chevron_left_rounded),
          label: Text(
            S.t('tutorialBack'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 10),
      ],
      FilledButton.icon(
        key: ValueKey(
          page == pageCount - 1 ? 'tutorial_finish' : 'tutorial_next',
        ),
        onPressed: onNext,
        style: FilledButton.styleFrom(
          backgroundColor: page == pageCount - 1
              ? const Color(0xFF43A047)
              : kCandyGold,
          foregroundColor: page == pageCount - 1
              ? kCandyCream
              : kChocolateOutline,
          minimumSize: Size(page == pageCount - 1 ? 156 : 104, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kChocolateOutline, width: 2),
          ),
        ),
        icon: Icon(
          page == pageCount - 1
              ? Icons.science_rounded
              : Icons.chevron_right_rounded,
        ),
        label: Text(
          S.t(page == pageCount - 1 ? 'tutorialStart' : 'tutorialNext'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );
}

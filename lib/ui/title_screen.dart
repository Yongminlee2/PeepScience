import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'theme.dart';

/// 앱을 열면 가장 먼저 나오는 메인 화면.
///
/// 전에는 월드 목록이 곧바로 떠서 "시작했다"는 느낌 없이 게임에 던져졌다.
/// 여기서 한 박자 쉬고 들어간다 - 큰 [시작하기] 하나, 그리고 들어가기 전에
/// 언어를 고를 수 있게 설정 버튼.
class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 설정에서 언어를 바꾸면 이 화면 글자도 같이 바뀌어야 한다.
    return ValueListenableBuilder<String>(
      valueListenable: AppLang(),
      builder: (context, _, _) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kHomeCanvasTop, kHomeCanvasBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        // 작은 가로 화면에서도 넘치지 않도록, 넘칠 때만 통째로
                        // 조금 줄인다.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: Image.asset(
                                    'store/art/icon_6.png',
                                    width: 132,
                                    height: 132,
                                    fit: BoxFit.cover,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  S.t('appTitle'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  S.t('homeTagline'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                ),
                                const SizedBox(height: 26),
                                _PlayButton(
                                  label: S.t('play'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const HomeScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 12,
                        child: IconButton(
                          key: const ValueKey('title_settings'),
                          iconSize: 34,
                          tooltip: S.t('settings'),
                          icon: const Icon(Icons.settings_rounded),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const ValueKey('title_play'),
    onPressed: onPressed,
    icon: const Icon(Icons.play_arrow_rounded, size: 32),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: kCandyGold,
      foregroundColor: kChocolateOutline,
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: kChocolateOutline, width: 3),
      ),
    ),
  );
}

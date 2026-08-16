import 'package:flutter/material.dart';

/// Padding for the trailing edge of a scrollable so its last item isn't
/// hidden behind the system bars in edge-to-edge mode (targetSdk 35+ always
/// draws edge-to-edge - PiyakPush hit this with its own scrolling stage
/// list). Apply as the `padding:` of any ListView/GridView that can scroll
/// content under a system bar.
EdgeInsets scrollPadding(BuildContext context) =>
    MediaQuery.viewPaddingOf(context);

/// World card theme colors, in world order (1-5): 크림 cream / 연두 light
/// green / 연보라 light lavender / 남색 navy / 칠판 초록 chalkboard green -
/// the home screen world cards' fixed palette. Also the errorBuilder
/// fallback fill for each card's bg-image thumbnail header (see
/// home_screen.dart's `_WorldCard`) when that world's bg asset
/// (`assets/images/bg/worldN.png`) fails to load.
const List<Color> worldCardColors = [
  Color(0xFFFFF6DE),
  Color(0xFFD9F2C4),
  Color(0xFFE3D4F5),
  Color(0xFF25316D),
  Color(0xFF2F5D50),
];

// 캔디 스티커 재질 언어(lib/game/hud.dart의 _kOutline/_kCardBg/_kCountChip과
// 같은 값) - 손맛 패스에서 홈 화면 월드 카드도 게임 HUD와 같은 재질로
// 읽히도록. hud.dart의 상수는 private이라 값만 그대로 다시 적는다.
const Color kChocolateOutline = Color(0xFF4E342E);
const Color kCandyCream = Color(0xFFFFFBF0);
const Color kCandyGold = Color(0xFFFFCA28);
const Color kHomeCanvasTop = Color(0xFFFFFAF4);
const Color kHomeCanvasBottom = Color(0xFFF4ECF8);

/// Shared Material shell for the non-game screens. The game itself is
/// painted by Flame, but home/settings should still feel like the same warm
/// candy-and-chocolate product instead of stock Material scaffolding.
ThemeData piyakTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kCandyGold,
    brightness: Brightness.light,
    surface: kCandyCream,
  ),
  scaffoldBackgroundColor: kHomeCanvasTop,
  appBarTheme: const AppBarTheme(
    backgroundColor: kHomeCanvasTop,
    foregroundColor: kChocolateOutline,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      color: kChocolateOutline,
      fontWeight: FontWeight.w900,
    ),
    titleLarge: TextStyle(
      color: kChocolateOutline,
      fontWeight: FontWeight.w800,
    ),
    bodyLarge: TextStyle(color: kChocolateOutline),
  ),
  dividerColor: kChocolateOutline.withAlpha(36),
);

import 'package:flutter/material.dart';

/// Padding for the trailing edge of a scrollable so its last item isn't
/// hidden behind the system bars in edge-to-edge mode (targetSdk 35+ always
/// draws edge-to-edge - PiyakPush hit this with its own scrolling stage
/// list). Apply as the `padding:` of any ListView/GridView that can scroll
/// content under a system bar.
EdgeInsets scrollPadding(BuildContext context) =>
    MediaQuery.viewPaddingOf(context);

/// World card theme colors, in world order (1-4): 크림 cream / 연두 light
/// green / 연보라 light lavender / 남색 navy - the shared-contract's fixed
/// 4-color palette for the home screen's world cards. Also the errorBuilder
/// fallback fill for each card's bg-image thumbnail header (see
/// home_screen.dart's `_WorldCard`) when that world's bg asset
/// (`assets/images/bg/worldN.png`) fails to load.
const List<Color> worldCardColors = [
  Color(0xFFFFF6DE),
  Color(0xFFD9F2C4),
  Color(0xFFE3D4F5),
  Color(0xFF25316D),
];

// 캔디 스티커 재질 언어(lib/game/hud.dart의 _kOutline/_kCardBg/_kCountChip과
// 같은 값) - 손맛 패스에서 홈 화면 월드 카드도 게임 HUD와 같은 재질로
// 읽히도록. hud.dart의 상수는 private이라 값만 그대로 다시 적는다.
const Color kChocolateOutline = Color(0xFF4E342E);
const Color kCandyCream = Color(0xFFFFFBF0);
const Color kCandyGold = Color(0xFFFFCA28);

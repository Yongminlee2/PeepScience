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
/// 4-color palette for the home screen's world cards.
const List<Color> worldCardColors = [
  Color(0xFFFFF6DE),
  Color(0xFFD9F2C4),
  Color(0xFFE3D4F5),
  Color(0xFF25316D),
];

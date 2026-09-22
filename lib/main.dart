import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ads.dart';
import 'services/sound.dart';
import 'ui/home_screen.dart';
import 'ui/settings_screen.dart' show soundEnabledPrefKey;
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // 효과음 선로드 + 저장된 켬/끔 값 반영 - 둘 다 await 없이 발사한다(시작을
  // 막지 않음). 실패는 Sound와 이 함수 내부에서 전부 삼키므로 기본값(켬)으로
  // 안전하게 물러난다.
  unawaited(Sound.init());
  unawaited(_loadSoundPref());
  // 광고 SDK도 시작을 막지 않는다. 실패하면 광고 없이 게임만 돌아간다.
  unawaited(Ads.init());
  runApp(const PiyakScienceApp());
}

Future<void> _loadSoundPref() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    Sound.setEnabled(prefs.getBool(soundEnabledPrefKey) ?? true);
  } catch (_) {
    // 실패하면 Sound의 기본값(켬)을 그대로 둔다.
  }
}

class PiyakScienceApp extends StatelessWidget {
  const PiyakScienceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: piyakTheme(),
    home: const HomeScreen(),
  );
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// 스토어에 새 버전이 있으면 앱을 켤 때 업데이트 화면을 띄운다.
///
/// 구글 플레이의 인앱 업데이트를 쓴다. 플레이 스토어에서 받은 앱에서만
/// 동작하고, 직접 설치한 빌드(개발용 폰)나 인터넷이 없을 때는 조용히 아무
/// 일도 하지 않는다. 사용자가 업데이트 화면을 닫으면 게임은 그대로 이어진다.
class AppUpdate {
  AppUpdate._();

  static bool _checked = false;

  /// 앱을 켜고 첫 화면이 뜬 뒤 한 번만 부른다.
  static Future<void> checkOnLaunch() async {
    if (_checked || kIsWeb || !kReleaseMode || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final availability = info.updateAvailability;
      if (availability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        // 전에 시작한 업데이트가 중간에 끊겼으면 마저 끝낸다.
        await InAppUpdate.performImmediateUpdate();
        return;
      }
      if (availability != UpdateAvailability.updateAvailable) return;
      if (info.immediateUpdateAllowed) {
        // 플레이가 띄우는 전체 화면 업데이트. 받는 동안 기다렸다가 새 버전으로
        // 다시 켜진다.
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        // 즉시 업데이트를 못 쓰는 경우엔 뒤에서 받고, 다 받으면 설치한다.
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (_) {
      // 스토어 설치본이 아니거나 플레이 서비스를 못 쓰면 여기로 온다. 무시한다.
    }
  }
}

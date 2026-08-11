import 'dart:convert';

import 'package:piyak_science/sim/stage_data.dart';

/// Builds a minimal [StageData] from JSON snippets for `preset`/`tray`/
/// `solution` arrays. Shared by every test/sim/*_test.dart file.
StageData stage(String preset, String tray, String sol,
        {String goal = 'ball_in_basket'}) =>
    StageData.fromJson(jsonDecode('{"id":"t","world":1,"index":1,'
        '"goal":{"type":"$goal"},"preset":[$preset],"tray":[$tray],"solution":[$sol]}'));

/// Language registry: one table per language, plus the settings-screen list.
///
/// Adding a language is three edits: a new `<code>.dart` next to this file
/// carrying exactly [kEn]'s keys, an entry in [kStrings], and one in
/// [kLanguageOrder]/[kLanguageNames].
library;

import 'de.dart';
import 'en.dart';
import 'es.dart';
import 'fr.dart';
import 'id.dart';
import 'it.dart';
import 'ja.dart';
import 'ko.dart';
import 'pt.dart';
import 'ru.dart';
import 'th.dart';
import 'vi.dart';
import 'zh.dart';
import 'zh_hant.dart';

const Map<String, Map<String, String>> kStrings = {
  'en': kEn,
  'ko': kKo,
  'ja': kJa,
  'zh': kZh,
  'zh_Hant': kZhHant,
  'es': kEs,
  'pt': kPt,
  'de': kDe,
  'fr': kFr,
  'it': kIt,
  'ru': kRu,
  'id': kId,
  'vi': kVi,
  'th': kTh,
};

/// Settings-screen order. Korean and English first (author + fallback),
/// then the rest roughly by store reach.
const List<String> kLanguageOrder = [
  'ko',
  'en',
  'ja',
  'zh',
  'zh_Hant',
  'es',
  'pt',
  'de',
  'fr',
  'it',
  'ru',
  'id',
  'vi',
  'th',
];

/// Each language written in itself. A child scanning the list looks for the
/// shape of their own writing, not for an English word they cannot read —
/// this is also why these are never translated per-language.
const Map<String, String> kLanguageNames = {
  'ko': '한국어',
  'en': 'English',
  'ja': '日本語',
  'zh': '简体中文',
  'zh_Hant': '繁體中文',
  'es': 'Español',
  'pt': 'Português',
  'de': 'Deutsch',
  'fr': 'Français',
  'it': 'Italiano',
  'ru': 'Русский',
  'id': 'Bahasa Indonesia',
  'vi': 'Tiếng Việt',
  'th': 'ไทย',
};

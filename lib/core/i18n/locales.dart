// Conditional so Studio can load the brand parser, which imports this file, on
// the plain Dart VM. Under Flutter it is `package:flutter/widgets.dart`.
import 'package:flutter/widgets.dart' if (dart.library.mirrors) '../headless.dart'
    show TextDirection;

/// The languages the SOCLE knows how to render.
///
/// ARCHITECTURE-MOBILE.md §2.5, and the lesson from §7.3 of the brief: this
/// constant is **not** the authority for any brand. A brand's `locales` and
/// `defaultLocale` are the authority for that brand. This list only says what
/// the socle has dictionaries for.
///
/// The web socle got this wrong: a global constant listed the languages and
/// routing validated URLs against it rather than against the brand, so a brand
/// limited to fr/en answered happily on /de/... while its own language picker
/// offered two.
const List<String> kSocleSupportedLanguages = <String>[
  'en',
  'fr',
  'ar',
  'es',
  'sl',
  'de',
  'sq',
];

/// Languages written right-to-left, among those the socle supports.
const Set<String> kRtlLanguages = <String>{'ar'};

bool isRtlLanguage(String code) => kRtlLanguages.contains(code);

TextDirection directionFor(String code) =>
    isRtlLanguage(code) ? TextDirection.rtl : TextDirection.ltr;

/// Endonyms — each language named in itself, never translated.
/// A language picker that says "Arabic" to an Arabic speaker is a bug.
const Map<String, String> kLanguageEndonyms = <String, String>{
  'en': 'English',
  'fr': 'Français',
  'ar': 'العربية',
  'es': 'Español',
  'sl': 'Slovenščina',
  'de': 'Deutsch',
  'sq': 'Shqip',
};

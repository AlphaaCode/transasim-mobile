/// Text folding for matching and ordering: case, accents and Arabic spelling
/// variants removed, so what a person types and what the data holds compare
/// equal. In core because the catalogue's search and ordering AND the sign-up
/// country picker use it, and a module may not import another (rule L2).
library;

/// The form a query and a name are compared in: lower-cased, accents folded,
/// punctuation collapsed to single spaces. The same fold is applied to both
/// sides, so "Algerie" meets "Algérie" and "munchen" meets "München".
///
/// Any script survives: letters and digits of every alphabet are kept, which
/// is what lets an Arabic query reach Arabic names. (An earlier fold kept only
/// a-z and 0-9, so an Arabic query folded to nothing and filtered nothing.)
/// Arabic is folded the way people type it: vowel marks and tatweel dropped,
/// the hamza-carrying alefs to a bare alef, alef maqsura to ya, ta marbuta
/// to ha.
String foldForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    // Arabic harakat (U+064B-U+065F), superscript alef, tatweel.
    if ((rune >= 0x064B && rune <= 0x065F) || rune == 0x0670 || rune == 0x0640) continue;
    final ch = String.fromCharCode(rune);
    buffer.write(_fold[ch] ?? ch);
  }
  return buffer.toString().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
}

/// Latin letters with diacritics, and the Arabic letters with common spelling
/// variants. Complete for every name in place_names.g.dart: a test folds all
/// of them and fails on any Latin letter left outside a-z.
const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'æ': 'ae',
  'ç': 'c', 'č': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c',
  'ď': 'd', 'đ': 'd', 'ð': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ě': 'e', 'ę': 'e', 'ė': 'e',
  'ğ': 'g', 'ĝ': 'g', 'ġ': 'g', 'ģ': 'g',
  'ħ': 'h', 'ĥ': 'h',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i', 'į': 'i', 'ĩ': 'i',
  'ĵ': 'j', 'ķ': 'k',
  'ł': 'l', 'ľ': 'l', 'ĺ': 'l', 'ļ': 'l',
  'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ņ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'œ': 'oe',
  'ř': 'r', 'ŕ': 'r',
  'š': 's', 'ś': 's', 'ș': 's', 'ş': 's', 'ŝ': 's', 'ß': 'ss',
  'ť': 't', 'ț': 't', 'ţ': 't', 'þ': 'th',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ũ': 'u', 'ŭ': 'u',
  'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
  'ž': 'z', 'ź': 'z', 'ż': 'z',
  // Apostrophes join rather than split: "Côte d’Ivoire" folds with "cote divoire".
  'ʻ': '', '’': '', "'": '', 'ʼ': '',
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
  'ى': 'ي', 'ئ': 'ي', 'ؤ': 'و', 'ة': 'ه',
};

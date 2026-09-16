/// Country names in the interface language.
///
/// The backend names every country in English only. The app shows the name the
/// user's language uses, from Unicode CLDR (country_names.g.dart), and falls
/// back to the backend's own string for a code CLDR does not know.
///
/// For structured country fields only — a destination, a coverage list, a
/// country picker. Product names the backend writes ("Best World", "One-off
/// EU28PLUS 500MB") are not country fields and are shown as sent.
library;

import 'country_names.g.dart';
import 'fold.dart';

String countryName(String code, String language, {required String fallback}) =>
    kCountryNamesByLanguage[language]?[code.toUpperCase()] ?? fallback;

/// Alphabetical order a reader of any served language expects. Comparing raw
/// strings puts "États-Unis" after "Zimbabwe" and splits Arabic names by which
/// alef they start with; comparing folded text keeps them in place.
int compareCountryNames(String a, String b) {
  final byFolded = foldForSearch(a).compareTo(foldForSearch(b));
  return byFolded != 0 ? byFolded : a.compareTo(b);
}

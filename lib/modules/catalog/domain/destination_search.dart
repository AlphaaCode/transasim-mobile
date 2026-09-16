/// Finding a destination by whatever the traveller types: the backend's name,
/// the ISO code, the country's name in any of the socle's seven languages,
/// or its capital in any of them — "Algerien", "الجزائر", "Alger", "Wien".
///
/// Both sides are folded ([foldForSearch]) so accents and case never matter.
/// Exact containment comes first; only when nothing contains the query does a
/// small edit-distance allowance look for a misspelling ("Algeriaa",
/// "Alegria"). Kept as a fallback on purpose: tolerance applied to every query
/// would make "Zambia" also list Gambia and "Iran" list Iraq.
///
/// Client-side, over ~250 countries: every name is folded once, then each
/// keystroke is a containment scan, plus a bounded distance check only when
/// the scan comes back empty.
library;

import '../../../core/i18n/country_names.g.dart';
import 'capitals.dart';
import 'place_names.g.dart';

/// The items whose destination matches [query], in their original order.
/// An empty query keeps everything.
List<T> searchDestinations<T>(
  List<T> items,
  String query, {
  required String Function(T) code,
  required String Function(T) name,
}) {
  final q = foldForSearch(query);
  if (q.isEmpty) return items;

  final exact = [
    for (final item in items)
      if (_termsOf(code(item), name(item)).any((t) => t.contains(q))) item,
  ];
  if (exact.isNotEmpty || q.length < _fuzzyFrom) return exact;

  final allowance = q.length >= 9 ? 2 : 1;
  return [
    for (final item in items)
      if (_termsOf(code(item), name(item)).any((t) => _near(q, t, allowance))) item,
  ];
}

/// Below this many characters a single edit is too large a share of the word:
/// "mali" would be one letter from "bali", "oman" from "iran".
const _fuzzyFrom = 4;

final Map<String, List<String>> _terms = {};

/// Every folded name for a destination, computed once per code.
List<String> _termsOf(String code, String name) {
  final iso3 = code.toUpperCase();
  return _terms.putIfAbsent('$iso3|$name', () {
    final raw = <String>{
      name,
      iso3,
      ...capitalsOf(iso3),
      for (final names in kCountryNamesByLanguage.values) ?names[iso3],
      ...?kCountryAltNames[iso3],
      ...?kCapitalNames[iso3],
    };
    return {for (final r in raw) foldForSearch(r)}.where((t) => t.isNotEmpty).toList();
  });
}

/// A misspelling of [term], or of one of its words, or of the start of one
/// (the traveller may not have finished typing).
bool _near(String query, String term, int allowance) {
  for (final word in {term, ...term.split(' ')}) {
    if ((word.length - query.length).abs() <= allowance &&
        editDistance(query, word, allowance) <= allowance) {
      return true;
    }
    if (word.length > query.length &&
        editDistance(query, word.substring(0, query.length), allowance) <= allowance) {
      return true;
    }
  }
  return false;
}

/// Optimal string alignment distance — Levenshtein plus the swap of two
/// adjacent letters, the commonest typing slip — capped: once every path
/// exceeds [cap], it stops and returns `cap + 1`.
int editDistance(String a, String b, int cap) {
  if ((a.length - b.length).abs() > cap) return cap + 1;
  var prevPrev = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = prev[j] + 1;
      if (row[j - 1] + 1 < best) best = row[j - 1] + 1;
      if (prev[j - 1] + cost < best) best = prev[j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
          prevPrev[j - 2] + 1 < best) {
        best = prevPrev[j - 2] + 1;
      }
      row[j] = best;
      if (best < rowMin) rowMin = best;
    }
    if (rowMin > cap) return cap + 1;
    prevPrev = prev;
    prev = row;
  }
  return prev[b.length];
}

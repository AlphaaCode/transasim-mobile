/// Finding the pack for a trip through several countries.
///
/// Rule, as specified: keep the packs whose countries include every chosen
/// one; the fewest total countries wins; cheaper breaks a tie.
///
/// Ranked by COVERAGE, not by pack. Packs sharing one country list are one
/// option, priced from its cheapest pack. Ranking the packs themselves fills
/// the top of the list with sizes of a single family: for UK + Australia +
/// France on the live catalogue, the first six packs are all Best World (500MB,
/// 1GB, 3GB...), and World — a real alternative — never shows. The sizes are
/// still one tap away inside each option.
///
/// When no pack covers everything, the options that cover the most of the
/// chosen countries are returned instead, flagged as partial.
library;

import 'catalog.dart';

class CoverageOption {
  /// Every country these packs cover, ISO3.
  final Set<String> countries;

  /// The packs sharing this coverage, cheapest first.
  final List<Pack> packs;

  /// Which of the chosen countries this covers, and which it does not.
  final Set<String> covered;
  final Set<String> missing;

  const CoverageOption({
    required this.countries,
    required this.packs,
    required this.covered,
    required this.missing,
  });

  bool get coversAll => missing.isEmpty;

  /// Countries included beyond the ones asked for.
  int get extra => countries.length - covered.length;

  Money? get from => packs.first.price;
}

class CoverageMatch {
  /// True when every option covers all the chosen countries; false when none
  /// does and these are the closest partial matches.
  final bool complete;
  final List<CoverageOption> options;

  const CoverageMatch({required this.complete, required this.options});
}

CoverageMatch matchCoverage(Iterable<Pack> packs, Set<String> chosen, {int limit = 5}) {
  final wanted = {for (final c in chosen) c.toUpperCase()};
  final groups = <String, List<Pack>>{};
  final countriesOf = <String, Set<String>>{};
  final seen = <int>{};

  for (final pack in packs) {
    // The same pack appears under every destination it covers.
    if (!seen.add(pack.id) || pack.price == null || pack.countryCodes.isEmpty) continue;
    final countries = {for (final c in pack.countryCodes) c.toUpperCase()};
    final key = (countries.toList()..sort()).join(',');
    (groups[key] ??= []).add(pack);
    countriesOf[key] = countries;
  }

  final options = <CoverageOption>[
    for (final MapEntry(:key, value: list) in groups.entries)
      CoverageOption(
        countries: countriesOf[key]!,
        packs: list..sort(_byPrice),
        covered: wanted.intersection(countriesOf[key]!),
        missing: wanted.difference(countriesOf[key]!),
      ),
  ];

  final complete = options.where((o) => o.coversAll).toList()
    ..sort((a, b) {
      final byCount = a.countries.length.compareTo(b.countries.length);
      if (byCount != 0) return byCount;
      return _byPrice(a.packs.first, b.packs.first);
    });
  if (complete.isNotEmpty) {
    return CoverageMatch(complete: true, options: complete.take(limit).toList());
  }

  final partial = options.where((o) => o.covered.isNotEmpty).toList()
    ..sort((a, b) {
      final byCovered = b.covered.length.compareTo(a.covered.length);
      if (byCovered != 0) return byCovered;
      final byCount = a.countries.length.compareTo(b.countries.length);
      if (byCount != 0) return byCount;
      return _byPrice(a.packs.first, b.packs.first);
    });
  return CoverageMatch(complete: false, options: partial.take(limit).toList());
}

/// For ordering only — the amount sent to checkout is the untouched string.
int _byPrice(Pack a, Pack b) {
  final byPrice = a.price!.value.compareTo(b.price!.value);
  return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
}

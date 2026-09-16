// Generates, in every language the socle serves:
//  - lib/core/i18n/country_names.g.dart: what each language calls a country,
//    shown in place of the backend's English names;
//  - lib/modules/catalog/domain/place_names.g.dart: alternate country names
//    and capital names, for destination search only.
//
// Run:  dart run tool/gen_place_names.dart
//
// Two established sources, nothing typed by hand:
//
//  - Country names: Unicode CLDR territory display names (cldr-json), the data
//    ICU and Flutter's own localisations are built on. Alternate names CLDR
//    records ("Swaziland", "Ivory Coast", "Aotearoa") are kept: people type them.
//  - Capital names: Wikidata (P36, current statements only), labels in the same
//    languages. A Wikidata capital is kept only when one of its English labels
//    folds to a capital in the curated table (capitals.dart), so a historical or
//    mis-modelled statement can never add a wrong city.
//
// Build-time only. The app bundles the generated file and never fetches.

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/modules/catalog/domain/capitals.dart';

const languages = ['en', 'fr', 'ar', 'es', 'de', 'sl', 'sq'];
const cldr = 'https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json';

/// The backend's ISO3 where it differs from CLDR's: Kosovo has no official
/// alpha-3; CLDR says XKK, the catalogue says XKX.
const backendAliases = {'XKX': 'XK'};

Future<Object?> getJson(Uri uri, {Map<String, String> headers = const {}}) async {
  final client = HttpClient()..userAgent = 'transasim-mobile place-name generator';
  try {
    final req = await client.getUrl(uri);
    headers.forEach(req.headers.set);
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('${res.statusCode} $uri');
    return jsonDecode(await res.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

/// Wikidata's English label names a curated capital: equal after folding, or
/// containing it as whole words ("Washington, D.C." for Washington, "South
/// Tarawa" for Tarawa), with "St." read as "Saint". A different city — Aden
/// for Sana'a, Rawalpindi for Islamabad — never passes.
bool confirms(String wikidataEnglish, List<String> curated) {
  String norm(String s) =>
      ' ${foldForSearch(s).split(' ').map((w) => w == 'st' ? 'saint' : w).join(' ')} ';
  final w = norm(wikidataEnglish);
  return curated.any((c) => w.contains(norm(c)));
}

Future<void> main() async {
  final version = ((await getJson(Uri.parse('$cldr/cldr-core/package.json'))) as Map)['version'];

  // ISO3 -> ISO2, for every region CLDR gives an alpha-3.
  final mappings = ((await getJson(Uri.parse('$cldr/cldr-core/supplemental/codeMappings.json')))
      as Map)['supplemental']['codeMappings'] as Map;
  final alpha2Of = <String, String>{
    for (final MapEntry(:key, :value) in mappings.entries)
      if (key is String && key.length == 2 && value is Map && value['_alpha3'] is String)
        value['_alpha3'] as String: key,
    ...backendAliases,
  };

  // What each language calls a country (shown), and the alternate names CLDR
  // also records — "Swaziland", "Ivory Coast", "UK" — which are searched only.
  final displayOf2 = <String, Map<String, String>>{for (final l in languages) l: {}};
  final altsOf2 = <String, List<String>>{};
  for (final lang in languages) {
    final territories = ((await getJson(
      Uri.parse('$cldr/cldr-localenames-full/main/$lang/territories.json'),
    )) as Map)['main'][lang]['localeDisplayNames']['territories'] as Map;
    for (final MapEntry(:key, :value) in territories.entries) {
      final parts = (key as String).split('-alt-');
      if (parts.first.length != 2 || value is! String) continue;
      if (parts.length == 1) {
        displayOf2[lang]![parts.first] = value;
      } else {
        final list = altsOf2.putIfAbsent(parts.first, () => []);
        if (!list.contains(value)) list.add(value);
      }
    }
  }

  // Keyed from the alpha-3 side: two alpha-3s can share an alpha-2 (Kosovo is
  // XKK in CLDR and XKX in the catalogue), and both have to come out named.
  final display = <String, Map<String, String>>{
    for (final lang in languages)
      lang: {
        for (final MapEntry(key: iso3, value: iso2) in alpha2Of.entries)
          iso3: ?displayOf2[lang]![iso2],
      },
  };
  final altNames = <String, List<String>>{
    for (final MapEntry(key: iso3, value: iso2) in alpha2Of.entries) iso3: ?altsOf2[iso2],
  };

  // Capitals, from Wikidata, checked against the curated English table.
  final codes = capitalCountryCodes.toList()..sort();
  final query = '''
SELECT ?iso3 ?enLabel ?label WHERE {
  VALUES ?iso3 { ${codes.map((c) => '"$c"').join(' ')} }
  ?country wdt:P298 ?iso3 ; p:P36 ?statement .
  ?statement ps:P36 ?capital ; wikibase:rank ?rank .
  FILTER(?rank != wikibase:DeprecatedRank)
  FILTER NOT EXISTS { ?statement pq:P582 ?ended }
  ?capital rdfs:label ?enLabel . FILTER(LANG(?enLabel) = "en")
  ?capital rdfs:label ?label . FILTER(LANG(?label) IN (${languages.map((l) => '"$l"').join(', ')}))
}''';
  final sparql = (await getJson(
    Uri.https('query.wikidata.org', '/sparql', {'query': query}),
    headers: {'Accept': 'application/sparql-results+json'},
  )) as Map;

  final capitalNames = <String, List<String>>{};
  final unconfirmed = <String>{};
  for (final row in (sparql['results'] as Map)['bindings'] as List) {
    final iso3 = row['iso3']['value'] as String;
    final en = row['enLabel']['value'] as String;
    final label = row['label']['value'] as String;
    if (!confirms(en, capitalsOf(iso3))) {
      unconfirmed.add('$iso3: Wikidata "$en" is not ${capitalsOf(iso3)}');
      continue;
    }
    final list = capitalNames.putIfAbsent(iso3, () => []);
    if (!list.contains(label)) list.add(label);
  }

  final missingCountry = codes.where((c) => !display['en']!.containsKey(c)).toList();
  final missingCapital = codes.where((c) => !capitalNames.containsKey(c)).toList();

  String quote(String n) => jsonEncode(n).replaceAll(r'$', r'\$');
  String entries(Map<String, List<String>> m) => (m.keys.toList()..sort())
      .map((k) => "  '$k': [${m[k]!.map(quote).join(', ')}],")
      .join('\n');
  String perLanguage(Map<String, Map<String, String>> m) => languages.map((lang) {
        final rows = (m[lang]!.keys.toList()..sort())
            .map((k) => "    '$k': ${quote(m[lang]![k]!)},")
            .join('\n');
        return "  '$lang': {\n$rows\n  },";
      }).join('\n');

  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final header = '// GENERATED by tool/gen_place_names.dart on $today. Do not edit by hand.';

  // Display names live in core: the catalogue AND the sign-up country picker
  // show them, and a module may not import another (rule L2).
  File('lib/core/i18n/country_names.g.dart').writeAsStringSync('''
$header
//
// Unicode CLDR $version territory names, ${languages.join(' ')}.
//
// ignore_for_file: lines_longer_than_80_chars

/// What each language calls a country, by ISO 3166-1 alpha-3. What the app
/// SHOWS: the backend sends English only. Read it through `countryName`.
const Map<String, Map<String, String>> kCountryNamesByLanguage = {
${perLanguage(display)}
};
''');

  // Search-only data stays with the search.
  File('lib/modules/catalog/domain/place_names.g.dart').writeAsStringSync('''
$header
//
// Alternate country names: Unicode CLDR $version, ${languages.join(' ')}.
// Capital names: Wikidata P36 labels in the same languages, kept only where the
// English label matches the curated table in capitals.dart.
//
// ignore_for_file: lines_longer_than_80_chars

/// The other names CLDR records ("Swaziland", "Ivory Coast", "UK"): searched,
/// never shown.
const Map<String, List<String>> kCountryAltNames = {
${entries(altNames)}
};

/// Wikidata labels for a country's capital(s), by alpha-3, all languages.
/// Searched, never shown.
const Map<String, List<String>> kCapitalNames = {
${entries(capitalNames)}
};
''');

  stdout
    ..writeln('CLDR $version: ${display['en']!.length} countries x ${languages.length} languages; Wikidata: ${capitalNames.length} capitals')
    ..writeln('catalogue codes without CLDR names: $missingCountry')
    ..writeln('catalogue codes without confirmed Wikidata capitals: $missingCapital')
    ..writeln('Wikidata capitals rejected by the curated table (${unconfirmed.length}):')
    ..writeAll(unconfirmed.map((u) => '  $u\n'));
}

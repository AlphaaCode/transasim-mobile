// Generates lib/modules/catalog/domain/place_names.g.dart: what a traveller
// might type for a destination, in every language the socle serves.
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

  // ISO2 -> names, across the languages, each language's primary name first.
  final namesOf2 = <String, List<String>>{};
  for (final lang in languages) {
    final territories = ((await getJson(
      Uri.parse('$cldr/cldr-localenames-full/main/$lang/territories.json'),
    )) as Map)['main'][lang]['localeDisplayNames']['territories'] as Map;
    for (final MapEntry(:key, :value) in territories.entries) {
      final code = (key as String).split('-alt-').first;
      if (code.length != 2 || value is! String) continue;
      final list = namesOf2.putIfAbsent(code, () => []);
      if (!list.contains(value)) list.add(value);
    }
  }

  final countryNames = <String, List<String>>{
    for (final MapEntry(key: iso3, value: iso2) in alpha2Of.entries)
      iso3: ?namesOf2[iso2],
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

  final missingCountry = codes.where((c) => !countryNames.containsKey(c)).toList();
  final missingCapital = codes.where((c) => !capitalNames.containsKey(c)).toList();

  String entries(Map<String, List<String>> m) => (m.keys.toList()..sort())
      .map((k) => "  '$k': [${m[k]!.map((n) => jsonEncode(n).replaceAll(r'$', r'\$')).join(', ')}],")
      .join('\n');

  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  File('lib/modules/catalog/domain/place_names.g.dart').writeAsStringSync('''
// GENERATED by tool/gen_place_names.dart on $today. Do not edit by hand.
//
// Country names: Unicode CLDR $version territory names, ${languages.join(' ')}.
// Capital names: Wikidata P36 labels in the same languages, kept only where the
// English label matches the curated table in capitals.dart.
//
// ignore_for_file: lines_longer_than_80_chars

/// Every CLDR name for a country, by ISO 3166-1 alpha-3, all languages.
const Map<String, List<String>> kCountryNames = {
${entries(countryNames)}
};

/// Wikidata labels for a country's capital(s), by alpha-3, all languages.
const Map<String, List<String>> kCapitalNames = {
${entries(capitalNames)}
};
''');

  stdout
    ..writeln('CLDR $version: ${countryNames.length} countries; Wikidata: ${capitalNames.length} capitals')
    ..writeln('catalogue codes without CLDR names: $missingCountry')
    ..writeln('catalogue codes without confirmed Wikidata capitals: $missingCapital')
    ..writeln('Wikidata capitals rejected by the curated table (${unconfirmed.length}):')
    ..writeAll(unconfirmed.map((u) => '  $u\n'));
}

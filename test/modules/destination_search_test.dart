import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/i18n/country_names.dart';
import 'package:transasim_mobile/core/i18n/country_names.g.dart';
import 'package:transasim_mobile/modules/catalog/domain/capitals.dart';
import 'package:transasim_mobile/modules/catalog/domain/destination_search.dart';
import 'package:transasim_mobile/modules/catalog/domain/place_names.g.dart';
import 'package:transasim_mobile/modules/catalog/presentation/catalog_controllers.dart';
import 'package:transasim_mobile/modules/catalog/domain/catalog.dart';

/// Destination search over the whole catalogue, not a handful of fixtures:
/// one entry per country the curated capitals cover, named in English the way
/// the backend names them.

final _world = [
  for (final code in capitalCountryCodes) (code: code, name: kCountryNamesByLanguage['en']![code]!),
];

final _allNames = [
  for (final byCode in kCountryNamesByLanguage.values) ...byCode.values,
  for (final names in kCountryAltNames.values) ...names,
  for (final names in kCapitalNames.values) ...names,
];

List<String> find(String query) =>
    searchDestinations(_world, query, code: (d) => d.code, name: (d) => d.name)
        .map((d) => d.code)
        .toList();

/// Found, AND actually filtered: a query that folds to nothing returns every
/// country, which would "contain" any code.
void expectFinds(String query, String code) {
  final found = find(query);
  expect(found, contains(code));
  expect(found.length, lessThan(10), reason: '"$query" should narrow the list, got ${found.length}');
}

void main() {
  group('"Alger" and Algeria: already a substring, and kept that way', () {
    test('the English country name contains it', () => expectFinds('Alger', 'DZA'));
    test('through the Store state, the path the screen uses', () {
      final state = CatalogReady(
        destinations: const [
          Destination(code: 'DZA', name: 'Algeria', packs: []),
          Destination(code: 'NGA', name: 'Nigeria', packs: []),
        ],
        query: 'Alger',
      );
      expect(state.visible.map((d) => d.code), ['DZA']);
    });
  });

  group('country names in every served language (CLDR)', () {
    for (final (query, code) in [
      ('Algérie', 'DZA'), // fr
      ('الجزائر', 'DZA'), // ar
      ('Argelia', 'DZA'), // es
      ('Algerien', 'DZA'), // de
      ('Alžirija', 'DZA'), // sl
      ('Algjeri', 'DZA'), // sq
      ('Österreich', 'AUT'),
      ('Royaume-Uni', 'GBR'),
      ('المملكة المتحدة', 'GBR'),
      ('Vereinigte Staaten', 'USA'),
      ('Swaziland', 'SWZ'), // a name CLDR keeps as an alternative
    ]) {
      test('"$query" finds $code', () => expectFinds(query, code));
    }
  });

  group('capitals in every served language (Wikidata, checked against the curated table)', () {
    for (final (query, code) in [
      ('Alger', 'DZA'),
      ('Londres', 'GBR'),
      ('لندن', 'GBR'),
      ('Wien', 'AUT'),
      ('الرياض', 'SAU'),
      ('Pékin', 'CHN'),
      ('Varsovie', 'POL'),
    ]) {
      test('"$query" finds $code', () => expectFinds(query, code));
    }

    test('a Wikidata city that is not the curated capital was not added', () {
      // Wikidata also lists Aden for Yemen; the curated capital is Sana'a.
      expect(find('Aden'), isNot(contains('YEM')));
    });
  });

  group('accents fold on both sides', () {
    test('typed without them', () {
      expectFinds('Algerie', 'DZA');
      expectFinds('Osterreich', 'AUT');
      expectFinds('Pekin', 'CHN');
    });
    test('typed with them against a name that has none', () => expectFinds('Álgeria', 'DZA'));
    test('Arabic vowel marks and hamza forms', () {
      expect(foldForSearch('الجَزَائِر'), 'الجزاير');
      expect(foldForSearch('أبوظبي'), 'ابوظبي');
    });
    test('an Arabic query filters instead of folding to nothing', () {
      expect(foldForSearch('الجزائر'), isNotEmpty);
      expect(find('الجزائر').length, lessThan(5));
    });

    test('every generated name folds to plain letters', () {
      // A Latin letter left outside a-z would be a missing entry in the fold
      // table: that name could never be matched without its accent.
      final latin = RegExp(r'[À-ɏḀ-ỿ]');
      final leftovers = <String>{
        for (final n in _allNames)
          for (final m in latin.allMatches(foldForSearch(n))) m[0]!,
      };
      expect(leftovers, isEmpty);
      final vanished = [
        for (final n in _allNames)
          if (foldForSearch(n).isEmpty) n,
      ];
      expect(vanished, isEmpty, reason: 'a name that folds to nothing can never be found');
    });
  });

  group('typos: tolerated only when nothing matches exactly', () {
    for (final (query, code) in [
      ('Algeriaa', 'DZA'),
      ('Alegria', 'DZA'), // two letters swapped
      ('Algreia', 'DZA'),
      ('Oesterreich', 'AUT'),
      ('Germny', 'DEU'),
      ('Switzerlnd', 'CHE'),
    ]) {
      test('"$query" finds $code', () => expectFinds(query, code));
    }

    test('a correct name does not pull in its near neighbours', () {
      expect(find('Zambia'), isNot(contains('GMB')));
      expect(find('Gambia'), isNot(contains('ZMB')));
      expect(find('Iran'), isNot(contains('IRQ')));
      expect(find('Austria'), isNot(contains('AUS')));
    });

    test('short queries get no tolerance', () {
      expect(find('Mali'), isNot(contains('BLR')));
      expect(find('xyz'), isEmpty);
    });

    test('nonsense stays empty', () => expect(find('qwertyuiop'), isEmpty));
  });

  group('shown names: the interface language, not the backend English', () {
    test('each served language has its own name', () {
      expect(countryName('DZA', 'fr', fallback: 'Algeria'), 'Algérie');
      expect(countryName('DZA', 'ar', fallback: 'Algeria'), 'الجزائر');
      expect(countryName('DZA', 'de', fallback: 'Algeria'), 'Algerien');
      expect(countryName('deu', 'es', fallback: 'Germany'), 'Alemania');
    });

    test('every catalogue country has a name in all seven languages', () {
      final missing = [
        for (final code in capitalCountryCodes)
          for (final lang in ['en', 'fr', 'ar', 'es', 'de', 'sl', 'sq'])
            if (kCountryNamesByLanguage[lang]?[code] == null) '$lang:$code',
      ];
      expect(missing, isEmpty);
    });

    test('Kosovo is named under the catalogue code XKX, not only CLDR XKK', () {
      expect(countryName('XKX', 'ar', fallback: 'Kosovo'), 'كوسوفو');
    });

    test('an unknown code, or a language CLDR data was not generated for, shows the backend name', () {
      expect(countryName('QQQ', 'fr', fallback: 'Nowhere'), 'Nowhere');
      expect(countryName('DZA', 'ja', fallback: 'Algeria'), 'Algeria');
    });

    test('lists order by the folded name: accents and alef forms do not push a name out of place', () {
      final fr = ['Zimbabwe', 'États-Unis', 'Espagne', 'Érythrée', 'Égypte']..sort(compareCountryNames);
      expect(fr, ['Égypte', 'Érythrée', 'Espagne', 'États-Unis', 'Zimbabwe']);
      final ar = ['اليابان', 'إسبانيا', 'ألمانيا', 'أستراليا']..sort(compareCountryNames);
      // Folded, إسبانيا reads اسب… and أستراليا است…: ب comes before ت.
      expect(ar, ['إسبانيا', 'أستراليا', 'ألمانيا', 'اليابان']);
    });

    test('capitals are search data only: nothing under lib/ shows them', () {
      // kCapitalNames and capitalsOf are for matching. If a screen ever needs a
      // capital, that is a new decision, not a reuse of this table.
      final users = [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !f.path.contains('catalog${Platform.pathSeparator}domain') &&
              RegExp(r'kCapitalNames|capitalsOf').hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(users, isEmpty);
    });
  });

  test('edit distance counts a swap as one edit and stops at its cap', () {
    expect(editDistance('algeria', 'algeria', 1), 0);
    expect(editDistance('algreia', 'algeria', 1), 1);
    expect(editDistance('algeriaa', 'algeria', 1), 1);
    expect(editDistance('zambia', 'gambia', 1), 1);
    expect(editDistance('abcdef', 'uvwxyz', 1), 2);
  });

  test('a keystroke over the whole catalogue stays instant, fallback included', () {
    find('warm up');
    final watch = Stopwatch()..start();
    for (final q in ['a', 'al', 'alg', 'alge', 'alger', 'algeri', 'algeriaa', 'qwertyuiop']) {
      find(q);
    }
    watch.stop();
    // Eight keystrokes, two of them through the typo fallback.
    expect(watch.elapsedMilliseconds, lessThan(400), reason: '${watch.elapsedMilliseconds} ms');
  });
}

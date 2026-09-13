import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/i18n/l10n.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/i18n/strings.dart';
import 'package:transasim_mobile/core/result/result.dart';

import 'brand_config_test.dart' show validJson;

BrandConfig brand({
  Map<String, dynamic>? texts,
  List<String> locales = const ['fr', 'en'],
  String defaultLocale = 'fr',
}) {
  final json = validJson()
    ..['locales'] = locales
    ..['defaultLocale'] = defaultLocale
    ..['name'] = 'Acme';
  if (texts != null) json['texts'] = texts;
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

void main() {
  group('the brand name is interpolated, never written', () {
    // Brief §7.1 / ANALYSE-EXISTANT.md §4.3: the old app had 88 occurrences of
    // the client's name across its 8 dictionaries, so the second client
    // inherited the first client's name in its own screens.

    test('{brand} is substituted from the config', () {
      final l = L10n(brand: brand(), language: 'en');
      expect(l.t('startup.welcome'), 'Welcome to Acme');
    });

    test('the same key under a different brand yields a different string', () {
      final acme = L10n(brand: brand(), language: 'en');
      final other = L10n(
        brand: BrandConfig.parse(validJson()..['name'] = 'Zenith', expectedSlug: 'acme')
            .config as BrandConfig,
        language: 'en',
      );
      expect(acme.t('startup.welcome'), isNot(other.t('startup.welcome')));
      expect(other.t('startup.welcome'), contains('Zenith'));
    });

    test('CI check C3: no client name appears in any dictionary', () {
      // The socle ships dictionaries for the product's vocabulary, not for one
      // client's discourse. This is the unit-test half of check C3.
      const clientNames = <String>['sabily', 'esimple', 'djezzy', 'castrum', 'transasim'];
      for (final entry in kStrings.entries) {
        for (final s in entry.value.values) {
          final lower = s.toLowerCase();
          for (final n in clientNames) {
            expect(lower, isNot(contains(n)),
                reason: 'dictionary "${entry.key}" contains the client name "$n"');
          }
        }
      }
    });
  });

  group('the override chain — §2.8', () {
    test('1. a brand override in the requested language wins', () {
      final l = L10n(
        brand: brand(texts: {
          'common.retry': {'en': 'Give it another go', 'fr': 'On retente'}
        }),
        language: 'en',
      );
      expect(l.t('common.retry'), 'Give it another go');
    });

    test("2. otherwise the brand's OWN default language, not the socle's", () {
      // The deliberate middle step. A brand that translated its message into
      // only two of six languages is better served by ITS message in the wrong
      // language than by another brand's message correctly translated.
      final l = L10n(
        brand: brand(
          texts: {
            'common.retry': {'fr': 'On retente'}
          },
          locales: ['fr', 'en', 'de'],
          defaultLocale: 'fr',
        ),
        language: 'de',
      );
      expect(l.t('common.retry'), 'On retente');
    });

    test('3. otherwise the socle dictionary in the requested language', () {
      final l = L10n(brand: brand(), language: 'fr');
      expect(l.t('common.retry'), 'Réessayer');
    });

    test('4. otherwise the reference language', () {
      final l = L10n(brand: brand(locales: ['fr', 'en']), language: 'fr');
      // Every key exists in fr here, so force the tail by asking in a language
      // the socle has no table for.
      final fallback = L10n(brand: brand(), language: 'zz');
      expect(fallback.t('common.retry'), kStrings['en']!['common.retry']);
      expect(l.t('common.retry'), isNotEmpty);
    });
  });

  group('partially inert configuration is reported, never silent', () {
    test('an override aimed at no known key is named', () {
      // Brief §2.8: exactly the case where a client phones up saying their
      // change was ignored.
      final b = brand(texts: {
        'common.retry': {'en': 'ok'},
        'nonexistent.key': {'en': 'nothing points here'},
      });
      expect(L10n.unknownOverrideKeys(b), <String>['nonexistent.key']);
    });

    test('a fully valid override set reports nothing', () {
      final b = brand(texts: {
        'common.retry': {'en': 'ok'}
      });
      expect(L10n.unknownOverrideKeys(b), isEmpty);
    });
  });

  group('dictionary completeness', () {
    test('every socle language covers every reference key', () {
      for (final lang in kSocleSupportedLanguages) {
        expect(L10n.missingKeys(lang), isEmpty,
            reason: 'language "$lang" is missing keys; a gap falls back silently forever');
      }
    });

    test('every supported language has a table and an endonym', () {
      for (final lang in kSocleSupportedLanguages) {
        expect(kStrings.containsKey(lang), isTrue, reason: 'no dictionary for "$lang"');
        expect(kLanguageEndonyms[lang], isNotNull, reason: 'no endonym for "$lang"');
      }
    });

    test('Arabic is the only RTL language and it is served', () {
      expect(kRtlLanguages, <String>{'ar'});
      expect(isRtlLanguage('ar'), isTrue);
      expect(isRtlLanguage('fr'), isFalse);
    });
  });

  test('every AppError code has a message in every language', () {
    // HttpFailure used to return `http_<status>`, a key no dictionary held;
    // the first live 500 put a failed assertion on the sign-in screen. Every
    // presentation layer resolves `error.<code>`, so every code must resolve.
    final codes = <AppError>[
      const NetworkUnavailable(),
      const HttpFailure(400),
      const HttpFailure(500),
      const ContractViolation('x'),
      const SessionExpired(),
      const FeatureUnavailable('x'),
      const BrandUnusable([]),
    ].map((e) => 'error.${e.code}');
    for (final entry in kStrings.entries) {
      for (final key in codes) {
        expect(entry.value.containsKey(key), isTrue, reason: '${entry.key} lacks $key');
      }
    }
  });
}

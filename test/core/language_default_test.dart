import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';

import 'brand_config_test.dart' show validJson;

/// What a launch opens in. The rule changed on 23/09/2026: the brand's
/// `defaultLocale` no longer decides it — the device does, and English catches
/// everything the brand cannot serve.
///
/// The app always provides storage (bootstrap overrides it); so do these.
late SharedPreferences _prefs;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });
  group('a first launch: the device decides, English catches the rest', () {
    // The pure function, driven with the device list rather than a platform.
    String start(List<String> served, List<String> device, {String defaultLocale = 'fr'}) =>
        startingLanguage(
          served,
          defaultLocale: defaultLocale,
          deviceLanguages: [for (final l in device) Locale(l)],
        );

    test('a served device language wins', () {
      expect(start(['fr', 'en', 'ar'], ['ar']), 'ar');
      expect(start(['fr', 'en', 'ar'], ['fr']), 'fr');
    });

    test('an unserved device language falls back to English, NOT to defaultLocale', () {
      // The whole point of the change: Sabily defaults to "fr", and a Japanese
      // or Italian phone was opening the app in French.
      expect(start(['fr', 'en', 'ar'], ['ja'], defaultLocale: 'fr'), 'en');
      expect(start(['de', 'en'], ['it'], defaultLocale: 'de'), 'en');
    });

    test('a region is not a language: fr-CA, ar-DZ and de-AT are all served', () {
      expect(
        startingLanguage(['fr', 'en'],
            defaultLocale: 'fr', deviceLanguages: [const Locale('fr', 'CA')]),
        'fr',
      );
      expect(
        startingLanguage(['de', 'en'],
            defaultLocale: 'de', deviceLanguages: [const Locale('de', 'AT')]),
        'de',
      );
    });

    test("the device's second preference is used when the first is not served", () {
      // Someone whose phone lists Japanese then Arabic reads Arabic here;
      // PlatformDispatcher.locale alone would have sent them to English.
      expect(start(['fr', 'en', 'ar'], ['ja', 'ar']), 'ar');
    });

    test('a brand that does not serve English falls back to its own default', () {
      // Acorn serves only English, so this is hypothetical today — but falling
      // back to a language with no dictionary would show raw keys.
      expect(start(['fr'], ['ja'], defaultLocale: 'fr'), 'fr');
    });

    test('through the provider, with a brand that serves the device language', () {
      final json = validJson()
        ..['locales'] = ['fr', 'en', 'ar']
        ..['defaultLocale'] = 'fr';
      final cfg = BrandConfig.parse(json, expectedSlug: 'acme').config as BrandConfig;

      final c = ProviderContainer(
        overrides: [
          brandConfigProvider.overrideWithValue(cfg),
          sharedPreferencesProvider.overrideWithValue(_prefs),
        ],
      );
      addTearDown(c.dispose);

      // The test platform reports en-US, which this brand serves.
      expect(c.read(languageProvider), 'en');
    });
  });

  group('reported on a real device: the chosen language resets on a full close', () {
    BrandConfig brand() {
      final json = validJson()
        ..['locales'] = ['fr', 'en', 'ar']
        ..['defaultLocale'] = 'fr';
      return BrandConfig.parse(json, expectedSlug: 'acme').config as BrandConfig;
    }

    /// One app process. A fresh container over the same storage is exactly a
    /// kill and relaunch: memory gone, disk kept.
    ProviderContainer launch(SharedPreferences prefs, BrandConfig cfg) {
      final c = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(cfg),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('choosing a language writes it to storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cfg = brand();
      final first = launch(prefs, cfg);

      first.read(languageProvider.notifier).set('ar');

      expect(first.read(languageProvider), 'ar');
      expect(prefs.getString('app.language'), 'ar', reason: 'the choice must reach disk');
    });

    test('a cold start reads the stored choice instead of the brand default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cfg = brand();
      launch(prefs, cfg).read(languageProvider.notifier).set('en');

      final relaunched = launch(prefs, cfg);
      expect(relaunched.read(languageProvider), 'en');
    });

    test('a stored language the brand no longer serves is ignored', () async {
      SharedPreferences.setMockInitialValues({'app.language': 'de'});
      final prefs = await SharedPreferences.getInstance();
      // Falls through to the device/English rule, not to defaultLocale ("fr").
      expect(launch(prefs, brand()).read(languageProvider), 'en');
    });

    test('a brand refresh mid-session keeps the chosen language', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(brand()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      c.read(languageProvider.notifier).set('ar');
      // What _BrandHost does when a remote config arrives: a new brand value.
      c.updateOverrides([
        brandConfigProvider.overrideWithValue(brand()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      expect(c.read(languageProvider), 'ar');
    });
  });
}

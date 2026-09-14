import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';

import 'brand_config_test.dart' show validJson;

/// The app always provides storage (bootstrap overrides it); so do these.
late SharedPreferences _prefs;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });
  test('the language seeds from the BRAND default, not from anything else', () {
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

    expect(c.read(languageProvider), 'fr');
  });

  test('a brand defaulting to German seeds German', () {
    final json = validJson()
      ..['locales'] = ['de', 'en']
      ..['defaultLocale'] = 'de';
    final cfg = BrandConfig.parse(json, expectedSlug: 'acme').config as BrandConfig;

    final c = ProviderContainer(
      overrides: [
        brandConfigProvider.overrideWithValue(cfg),
        sharedPreferencesProvider.overrideWithValue(_prefs),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(languageProvider), 'de');
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

    test('a stored language the brand no longer serves falls back to the default', () async {
      SharedPreferences.setMockInitialValues({'app.language': 'de'});
      final prefs = await SharedPreferences.getInstance();
      expect(launch(prefs, brand()).read(languageProvider), 'fr');
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

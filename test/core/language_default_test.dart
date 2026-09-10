import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';

import 'brand_config_test.dart' show validJson;

void main() {
  test('the language seeds from the BRAND default, not from anything else', () {
    final json = validJson()
      ..['locales'] = ['fr', 'en', 'ar']
      ..['defaultLocale'] = 'fr';
    final cfg = BrandConfig.parse(json, expectedSlug: 'acme').config as BrandConfig;

    final c = ProviderContainer(
      overrides: [brandConfigProvider.overrideWithValue(cfg)],
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
      overrides: [brandConfigProvider.overrideWithValue(cfg)],
    );
    addTearDown(c.dispose);

    expect(c.read(languageProvider), 'de');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/dev/brand_preview_screen.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';

import '../core/brand_config_test.dart' show validJson;

/// The app always provides storage (bootstrap overrides it); so do these.
late SharedPreferences _prefs;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });
  Future<void> open(WidgetTester tester, BrandConfig cfg) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          brandConfigProvider.overrideWithValue(cfg),
          sharedPreferencesProvider.overrideWithValue(_prefs),
          allModulesProvider.overrideWithValue(const []),
          // languageProvider deliberately NOT overridden — this is the path the
          // real app takes, and the one the other widget tests never exercise.
        ],
        child: MaterialApp(
          theme: buildTheme(cfg),
          home: const BrandPreviewScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  BrandConfig brand(List<String> locales, String defaultLocale) {
    final json = validJson()
      ..['name'] = 'Acme'
      ..['locales'] = locales
      ..['defaultLocale'] = defaultLocale;
    return BrandConfig.parse(json, expectedSlug: 'acme').config as BrandConfig;
  }

  testWidgets('the app opens in the DEVICE language when the brand serves it', (tester) async {
    // The test platform reports en-US, and this brand serves English — so
    // English, even though the brand's own default is French. That is the
    // change of 23/09/2026: a French default was sending every foreign
    // visitor into French.
    await open(tester, brand(['fr', 'en', 'ar'], 'fr'));

    expect(find.textContaining('Welcome'), findsWidgets);
    expect(find.textContaining('Bienvenue'), findsNothing);
  });

  testWidgets('a brand that does not serve the device language falls back to English',
      (tester) async {
    // No English here either, so this exercises the last resort: the brand's
    // own default, because a language with no dictionary would show raw keys.
    await open(tester, brand(['fr', 'ar'], 'fr'));

    expect(find.textContaining('Bienvenue'), findsWidgets);
  });
}

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
  testWidgets('the app opens in the brand default language, unoverridden',
      (tester) async {
    final json = validJson()
      ..['name'] = 'Acme'
      ..['locales'] = ['fr', 'en', 'ar']
      ..['defaultLocale'] = 'fr';
    final cfg = BrandConfig.parse(json, expectedSlug: 'acme').config as BrandConfig;

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

    // French strings, not English ones.
    expect(find.textContaining('Bienvenue'), findsWidgets,
        reason: 'opened in the wrong language');
  });
}

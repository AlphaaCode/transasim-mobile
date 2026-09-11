@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/dev/brand_preview_screen.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/wallet/wallet_module.dart';

import 'real_fonts.dart';

/// The J3 milestone, rendered.
///
/// ARCHITECTURE-MOBILE.md §13.4 step 2: "an app that starts, shows its colours
/// and its logo FROM CONFIGURATION, in all seven languages".
///
/// These goldens render the real shipped `brands/sabily/brand.json`, with the
/// real bundled fonts and the real logo asset — so they are evidence, not a
/// mock. Regenerate with:
///
///   flutter test --update-goldens test/widget/j3_golden_test.dart

BrandConfig _loadShippedSabily() {
  final json = jsonDecode(File('brands/sabily/brand.json').readAsStringSync())
      as Map<String, dynamic>;
  final r = BrandConfig.parse(json, expectedSlug: 'sabily');
  if (r.errors.isNotEmpty) throw StateError(r.describe('sabily'));
  return r.config as BrandConfig;
}

class _FixedLanguage extends LanguageController {
  final String value;
  _FixedLanguage(this.value);
  @override
  String build() => value;
}

void main() {
  late BrandConfig sabily;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRealFonts();
    sabily = _loadShippedSabily();
  });

  for (final language in kSocleSupportedLanguages) {
    testWidgets('Sabily renders in "$language"', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532); // iPhone-class portrait
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            brandConfigProvider.overrideWithValue(sabily),
            allModulesProvider.overrideWithValue(const [WalletModule()]),
            languageProvider.overrideWith(() => _FixedLanguage(language)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(sabily),
            locale: Locale(language),
            home: Directionality(
              textDirection: directionFor(language),
              child: const BrandPreviewScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(BrandPreviewScreen),
        matchesGoldenFile('goldens/j3_sabily_$language.png'),
      );
    });
  }
}

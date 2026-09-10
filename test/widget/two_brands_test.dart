import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/dev/brand_preview_screen.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/wallet/wallet_module.dart';

import '../core/brand_config_test.dart' show validJson;

BrandConfig configure(Map<String, dynamic> Function(Map<String, dynamic>) mutate) {
  final r = BrandConfig.parse(mutate(validJson()), expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

/// Mounts a screen under one brand. Swapping brands is a single override —
/// which is the whole reason Riverpod was chosen (ARCHITECTURE-MOBILE.md §5.1).
Widget harness(BrandConfig brand, {String? language}) {
  return ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(brand),
      allModulesProvider.overrideWithValue(const [WalletModule()]),
      if (language != null) languageProvider.overrideWith(() => _FixedLanguage(language)),
    ],
    child: MaterialApp(
      theme: buildTheme(brand),
      locale: Locale(language ?? brand.defaultLocale),
      home: Directionality(
        textDirection: directionFor(language ?? brand.defaultLocale),
        child: const BrandPreviewScreen(),
      ),
    ),
  );
}

class _FixedLanguage extends LanguageController {
  final String value;
  _FixedLanguage(this.value);
  @override
  String build() => value;
}

void main() {
  final acme = configure((j) => j
    ..['name'] = 'Acme'
    ..['colors'] = {
      'primary': '#003c3a',
      'accent': '#d2f5ec',
      'surface': '#f9f2d3',
      'cta': '#fadb14',
      'ctaText': '#003c3a',
    });

  // Every brand-owned value differs, including the legal entity — the header
  // renders that too, and a fixture that changed only `name` would let a
  // leaked value pass unnoticed.
  final zenith = configure((j) => j
    ..['name'] = 'Zenith'
    ..['legal'] = {
      'companyName': 'Zenith GmbH',
      'country': 'AT',
      'termsUrl': 'https://zenith.test/terms',
      'privacyUrl': 'https://zenith.test/privacy',
      'vatRate': 20.0,
    }
    ..['colors'] = {
      'primary': '#101f5c',
      'accent': '#c9d4ff',
      'surface': '#f4f6ff',
      'cta': '#ff5a1f',
      'ctaText': '#ffffff',
    });

  group('the same screen under two brands — ARCHITECTURE-MOBILE.md §8.3', () {
    // The direct translation of acceptance criterion §3.3.2 of the brief. If
    // any brand value were hardcoded in a widget, this test could not pass.

    testWidgets('renders each brand name from configuration', (tester) async {
      await tester.pumpWidget(harness(acme, language: 'en'));
      await tester.pump();
      expect(find.textContaining('Acme'), findsWidgets);
      expect(find.textContaining('Zenith'), findsNothing);

      await tester.pumpWidget(harness(zenith, language: 'en'));
      await tester.pump();
      expect(find.textContaining('Zenith'), findsWidgets);
      expect(find.textContaining('Acme'), findsNothing);
    });

    testWidgets('derives a different theme for each brand', (tester) async {
      Color primaryOf(BrandConfig b) => buildTheme(b).extension<AppTokens>()!.primary;

      expect(primaryOf(acme), isNot(primaryOf(zenith)));
      expect(buildTheme(acme).scaffoldBackgroundColor,
          isNot(buildTheme(zenith).scaffoldBackgroundColor));

      await tester.pumpWidget(harness(zenith, language: 'en'));
      await tester.pump();
      final ctx = tester.element(find.byType(BrandPreviewScreen));
      expect(AppTokens.of(ctx).cta, const Color(0xFFFF5A1F));
    });

    testWidgets('offers only the languages THIS brand serves', (tester) async {
      final twoLanguages = configure((j) => j
        ..['locales'] = ['fr', 'en']
        ..['defaultLocale'] = 'fr');
      await tester.pumpWidget(harness(twoLanguages));
      await tester.pump();

      expect(find.text('Français'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      // The socle knows seven; this brand serves two. The brand is the
      // authority (§2.5) — the old web socle got this exactly backwards.
      expect(find.text('العربية'), findsNothing);
      expect(find.text('Deutsch'), findsNothing);
    });
  });

  group('Arabic and RTL are exercised from the first screen — §8.2', () {
    final arabic = configure((j) => j
      ..['locales'] = ['fr', 'ar']
      ..['defaultLocale'] = 'ar'
      ..['visuals'] = {
        'howItWorks': {'ltr': 'a.png', 'rtl': 'b.png'}
      });

    testWidgets('lays out right-to-left and renders Arabic text', (tester) async {
      await tester.pumpWidget(harness(arabic, language: 'ar'));
      await tester.pump();

      final dir = Directionality.of(tester.element(find.byType(BrandPreviewScreen)));
      expect(dir, TextDirection.rtl);

      // Resolved from the Arabic dictionary, with the brand interpolated.
      expect(find.textContaining('مرحبًا'), findsWidgets);
      expect(find.text('العربية'), findsOneWidget);
    });

    testWidgets('every language this brand serves renders without overflow',
        (tester) async {
      final allSeven = configure((j) => j
        ..['locales'] = kSocleSupportedLanguages
        ..['defaultLocale'] = 'fr');

      for (final lang in kSocleSupportedLanguages) {
        await tester.pumpWidget(harness(allSeven, language: lang));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'language "$lang" threw while rendering');
      }
    });
  });

  group('a disabled module contributes no navigation', () {
    testWidgets('the wallet tab is absent when the flag is off', (tester) async {
      await tester.pumpWidget(harness(acme, language: 'en'));
      await tester.pump();
      expect(find.text('Wallet'), findsNothing);
    });
  });
}

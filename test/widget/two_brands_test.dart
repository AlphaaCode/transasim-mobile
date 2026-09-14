import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      sharedPreferencesProvider.overrideWithValue(_prefs),
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

/// The app always provides storage (bootstrap overrides it); so do these.
late SharedPreferences _prefs;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });
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

  group('the two real clients, Sabily and eSimple, share no brand value', () {
    // The same check as above, on the shipped configurations rather than
    // fixtures. A value is "Sabily's" when it appears in Sabily's brand.json and
    // nowhere in eSimple's (and the reverse); none may reach the other's screen.
    BrandConfig real(String slug) {
      final json = jsonDecode(File('brands/$slug/brand.json').readAsStringSync());
      final r = BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: slug);
      if (r.errors.isNotEmpty) throw StateError(r.describe(slug));
      return r.config as BrandConfig;
    }

    Set<String> leaves(Object? node) => switch (node) {
          String s => {s},
          Map m => {for (final v in m.values) ...leaves(v)},
          List l => {for (final v in l) ...leaves(v)},
          _ => <String>{},
        };
    Set<String> rawLeaves(String slug) =>
        leaves(jsonDecode(File('brands/$slug/brand.json').readAsStringSync()));

    /// Everything a user can read on screen, and every image it draws.
    List<String> onScreen(WidgetTester tester) => [
          for (final t in tester.widgetList<Text>(find.byType(Text)))
            t.data ?? t.textSpan?.toPlainText() ?? '',
          for (final i in tester.widgetList<Image>(find.byType(Image)))
            if (i.image case AssetImage(:final assetName)) assetName,
        ];

    for (final (shown, other) in [('esimple', 'sabily'), ('sabily', 'esimple')]) {
      testWidgets('$shown shows nothing of $other', (tester) async {
        final brand = real(shown);
        final foreign = rawLeaves(other).difference(rawLeaves(shown))
          ..removeWhere((v) => v.length < 4);

        for (final language in brand.locales) {
          await tester.pumpWidget(harness(brand, language: language));
          await tester.pump();
          final texts = onScreen(tester);
          expect(texts, isNotEmpty);
          for (final text in texts) {
            expect(text.toLowerCase(), isNot(contains(other)), reason: '[$language] "$text"');
            for (final value in foreign) {
              expect(text, isNot(contains(value)), reason: '[$language] $other value "$value" in "$text"');
            }
          }
          // Its own identity is what IS shown.
          expect(texts.any((t) => t.contains(brand.name)), isTrue, reason: language);
          expect(texts, contains('brands/$shown/assets/${brand.logo.mark}'));
        }
      });
    }

    test('their themes differ on every brand colour', () {
      final a = buildTheme(real('sabily')).extension<AppTokens>()!;
      final b = buildTheme(real('esimple')).extension<AppTokens>()!;
      expect(a.primary, isNot(b.primary));
      expect(a.surface, isNot(b.surface));
      expect(a.cta, isNot(b.cta));
    });

    testWidgets('eSimple offers its six languages, and not Spanish', (tester) async {
      await tester.pumpWidget(harness(real('esimple'), language: 'de'));
      await tester.pump();
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('Español'), findsNothing);
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

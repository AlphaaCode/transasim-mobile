@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/country_names.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/app_button.dart';
import 'package:transasim_mobile/core/ui/app_card.dart';
import 'package:transasim_mobile/modules/catalog/domain/catalog.dart';
import 'package:transasim_mobile/modules/catalog/presentation/catalog_controllers.dart';
import 'package:transasim_mobile/modules/catalog/presentation/destination_screen.dart';
import 'package:transasim_mobile/modules/catalog/presentation/store_screen.dart';

import 'real_fonts.dart';

/// The catalogue screens, rendered in French and in Arabic.
///
/// Arabic is exercised on every screen as it is built, not as a pass at the end
/// (ARCHITECTURE-MOBILE.md §8.2). The old app listed Arabic among its supported
/// languages and never designed for it once.
///
/// Regenerate:
///   flutter test --update-goldens test/widget/catalog_screens_test.dart

Money eur(String amount) => Money(wireAmount: amount, currencyCode: 'EUR', symbol: '€');

Pack pack(int id, String name, int gb, String price, {List<String> tags = const []}) => Pack(
      id: id,
      name: name,
      description: '$name package. Non-renewable.',
      data: DataAllowance(kilobytes: gb * 1024 * 1024, unlimited: false),
      validity: const Validity(amount: 30, unit: 'DAY'),
      price: eur(price),
      tags: tags,
      countryCodes: const ['FRA'],
      coverImageUrl: null,
    );

final _france = Destination(code: 'FRA', name: 'France', packs: [
  pack(1, 'One-off France 5GB 30 day(s)', 5, '9.99'),
  pack(4, 'Europe 20GB 30 day(s)', 20, '29.99', tags: ['POPULAR']),
]);

final _destinations = <Destination>[
  _france,
  Destination(code: 'JPN', name: 'Japan', packs: [pack(3, 'Japan 3GB', 3, '7.25')]),
  Destination(code: 'ESP', name: 'Spain', packs: [pack(2, 'Spain 10GB', 10, '16.50')]),
];

/// No network in a widget test. The repository contract is the seam.
class _FakeCatalog implements CatalogRepository {
  @override
  Future<List<Destination>> destinations({bool refresh = false}) async => _destinations;

  @override
  Future<Destination?> destination(String code) async =>
      _destinations.where((d) => d.code == code).firstOrNull;
}

class _FixedLanguage extends LanguageController {
  final String value;
  _FixedLanguage(this.value);
  @override
  String build() => value;
}


BrandConfig _sabily() {
  final json =
      jsonDecode(File('brands/sabily/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final r = BrandConfig.parse(json, expectedSlug: 'sabily');
  if (r.errors.isNotEmpty) throw StateError(r.describe('sabily'));
  return r.config as BrandConfig;
}

Widget _host(BrandConfig brand, String language, Widget screen) => ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(brand),
        allModulesProvider.overrideWithValue(const []),
        languageProvider.overrideWith(() => _FixedLanguage(language)),
        catalogRepositoryProvider.overrideWithValue(_FakeCatalog()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brand),
        locale: Locale(language),
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => Directionality(
                textDirection: directionFor(language),
                child: screen,
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  late BrandConfig sabily;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRealFonts();
    sabily = _sabily();
  });

  testWidgets('picking a region keeps the gap under the multi-country card', (tester) async {
    // Every gap below that card used to live inside the `browsing` branch, and
    // the header sliver closes its own padding at 0 — so choosing a region hid
    // the popular shelf AND took the spacing with it, leaving the chip row
    // sitting flush against the card. Seen on device; the horizontal padding
    // was never the problem, the vertical gap was.
    await tester.pumpWidget(_host(sabily, 'fr', const StoreScreen()));
    await tester.pumpAndSettle();

    double gap() =>
        tester.getTopLeft(find.byType(AppFilterChip).first).dy -
        tester.getBottomLeft(find.byType(AppFeatureCard).first).dy;

    // Browsing: the shelf sits between the two, so the chips are well clear.
    expect(gap(), greaterThan(16), reason: 'browsing');

    // Now filter. The shelf goes away; the gap must not go with it.
    await tester.tap(find.byType(AppFilterChip).at(1));
    await tester.pumpAndSettle();

    expect(find.byType(AppFilterChip), findsWidgets);
    expect(gap(), greaterThanOrEqualTo(16),
        reason: 'a region is selected: the chip row must not touch the card');
  });

  testWidgets('a store screen rebuilt from scratch shows the query still filtering it', (tester) async {
    // Seen on device: leave the store with a search typed, come back, and the
    // field is empty while "All" still lists one country.
    final shown = ValueNotifier(true);
    await tester.pumpWidget(_host(
      sabily,
      'fr',
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (_, on, _) => on ? const StoreScreen() : const SizedBox(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Jap');
    await tester.pump();

    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Japon'), findsOneWidget);
    expect(find.text('France'), findsNothing);
    expect(find.widgetWithText(TextField, 'Jap'), findsOneWidget);
  });

  for (final language in ['fr', 'ar']) {
    testWidgets('store list in "$language"', (tester) async {
      tester.view.physicalSize = const Size(1170, 2100);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(sabily, language, const StoreScreen()));
      await tester.pumpAndSettle();

      // The destination is named in the interface language, not the backend's
      // English: "France" in French, "فرنسا" in Arabic.
      // findsWidgets, not findsOneWidget: a browsing Store now shows the most
      // covered destinations twice on purpose — once on the popular shelf and
      // once in the full list below it. What this pins is that BOTH say it in
      // the interface language.
      expect(find.text(countryName('FRA', language, fallback: 'France')), findsWidgets);
      if (language == 'ar') expect(find.text('France'), findsNothing);
      await expectLater(
        find.byType(StoreScreen),
        matchesGoldenFile('goldens/catalog_store_$language.png'),
      );
    });

    testWidgets('destination in "$language"', (tester) async {
      tester.view.physicalSize = const Size(1170, 4500);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(sabily, language, const DestinationScreen(code: 'FRA')),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(DestinationScreen),
        matchesGoldenFile('goldens/catalog_destination_$language.png'),
      );
    });
  }

  testWidgets('Arabic mirrors the destination header', (tester) async {
    await tester.pumpWidget(_host(sabily, 'ar', const DestinationScreen(code: 'FRA')));
    await tester.pumpAndSettle();

    expect(
      Directionality.of(tester.element(find.byType(DestinationScreen))),
      TextDirection.rtl,
    );
    // Resolved from the Arabic dictionary, not a hardcoded label.
    expect(find.textContaining('الباقات المتاحة'), findsWidgets);
  });

  testWidgets('a per-GB rate ignores unlimited packs rather than dividing by zero',
      (tester) async {
    // Guards the arithmetic behind the "€1.50 / GB" pill: 29.99/20 beats
    // 9.99/5, and the unlimited pack contributes nothing.
    expect(_france.bestPricePerGigabyte, closeTo(1.4995, 0.0001));
  });
}

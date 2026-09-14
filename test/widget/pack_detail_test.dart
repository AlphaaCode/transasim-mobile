import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/catalog/domain/catalog.dart';
import 'package:transasim_mobile/modules/catalog/presentation/catalog_controllers.dart';
import 'package:transasim_mobile/modules/catalog/presentation/destination_screen.dart';
import 'package:transasim_mobile/modules/catalog/presentation/pack_detail_screen.dart';

import 'real_fonts.dart';

/// The pack detail screen: reached from a card's body, built only from what a
/// pack really carries, and never a second step in front of the card's own
/// buy button.

Money _eur(String a) => Money(wireAmount: a, currencyCode: 'EUR', symbol: '€');

Pack _pack(int id, String name, List<String> countries) => Pack(
      id: id,
      name: name,
      description: null,
      data: const DataAllowance(kilobytes: 10 * 1024 * 1024, unlimited: false),
      validity: const Validity(amount: 30, unit: 'days'),
      price: _eur('21'),
      tags: const [],
      countryCodes: countries,
      coverImageUrl: null,
    );

/// A single-country pack and one covering eight countries.
final _world = _pack(2, 'One-off Best World 10GB', ['FRA', 'ESP', 'JPN', 'SAU', 'DZA', 'TUN', 'USA', 'KEN']);
final _destinations = <Destination>[
  Destination(code: 'FRA', name: 'France', packs: [_pack(1, 'One-off France 10GB', ['FRA']), _world]),
  for (final (code, name) in [
    ('ESP', 'Spain'), ('JPN', 'Japan'), ('SAU', 'Saudi Arabia'), ('DZA', 'Algeria'),
    ('TUN', 'Tunisia'), ('USA', 'United States'), ('KEN', 'Kenya'),
  ])
    Destination(code: code, name: name, packs: [_world]),
];

class _FakeCatalog implements CatalogRepository {
  @override
  Future<List<Destination>> destinations() async => _destinations;
  @override
  Future<Destination?> destination(String code) async =>
      _destinations.where((d) => d.code == code).firstOrNull;
}

Future<void> _pump(WidgetTester tester) async {
  final json =
      jsonDecode(File('brands/sabily/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final brand = BrandConfig.parse(json, expectedSlug: 'sabily').config as BrandConfig;
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/destination/FRA',
    routes: [
      GoRoute(
        path: '/destination/:code',
        builder: (_, s) => DestinationScreen(code: s.pathParameters['code']!),
      ),
      GoRoute(
        path: '/destination/:code/pack/:id',
        name: 'pack',
        builder: (_, s) => PackDetailScreen(
          destinationCode: s.pathParameters['code']!,
          packId: int.parse(s.pathParameters['id']!),
        ),
      ),
    ],
  );
  tester.view.physicalSize = const Size(1170, 5200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(brand),
      sharedPreferencesProvider.overrideWithValue(prefs),
      allModulesProvider.overrideWithValue(const []),
      catalogRepositoryProvider.overrideWithValue(_FakeCatalog()),
    ],
    child: MaterialApp.router(theme: buildTheme(brand), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets("the card's buy button stays a fast path; it does not open the detail",
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Acheter ce forfait').first);
    await tester.pumpAndSettle();
    // No checkout module in this harness, so the fast path says so and stays.
    expect(find.text('Détails du forfait'), findsNothing);
  });

  testWidgets('tapping a card body opens that pack, built from real data only', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('One-off Best World 10GB'));
    await tester.pumpAndSettle();

    expect(find.text('Détails du forfait'), findsOneWidget);
    expect(find.text('One-off Best World 10GB'), findsOneWidget);
    expect(find.text('21,00\u00A0€'), findsOneWidget);
    // The two stats that exist.
    expect(find.text('10 Go'), findsOneWidget);
    expect(find.text('30 jours'), findsOneWidget);
    // Nothing the data does not carry.
    expect(find.textContaining('4G'), findsNothing);
    expect(find.textContaining('5G'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
    // The buy bar carries the exact price.
    expect(find.text('Acheter ce forfait – 21,00\u00A0€'), findsOneWidget);
  });

  testWidgets('coverage lists the real countries, the destination first, the rest on demand',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('One-off Best World 10GB'));
    await tester.pumpAndSettle();

    expect(find.text('Couverture'), findsOneWidget);
    expect(find.text('8 pays'), findsOneWidget);

    final names = tester
        .widgetList<Text>(find.descendant(of: find.byType(Row), matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final france = names.indexOf('France');
    final algeria = names.indexOf('Algeria');
    expect(france, isNonNegative, reason: 'the destination leads');
    expect(france, lessThan(algeria), reason: 'then alphabetical');
    // Six shown, two behind the button.
    expect(find.text('Tunisia'), findsNothing);
    expect(find.text('United States'), findsNothing);

    await tester.tap(find.text('Voir les 8 pays'));
    await tester.pumpAndSettle();
    expect(find.text('Tunisia'), findsOneWidget);
    expect(find.text('United States'), findsOneWidget);
    expect(find.text('Afficher moins'), findsOneWidget);
  });

  testWidgets('a single-country pack says so, with no expander', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('One-off France 10GB'));
    await tester.pumpAndSettle();
    expect(find.text('1 pays'), findsOneWidget);
    expect(find.textContaining('Voir les'), findsNothing);
  });
}

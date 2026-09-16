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
import 'package:transasim_mobile/modules/catalog/presentation/trip_screens.dart';

import 'real_fonts.dart';

/// The multi-country finder, through its real screens: pick, see the ranking,
/// and be told plainly when no single pack covers the whole trip.

Pack _pack(int id, String name, String price, List<String> countries) => Pack(
      id: id,
      name: name,
      description: null,
      data: const DataAllowance(kilobytes: 1024 * 1024, unlimited: false),
      validity: const Validity(amount: 30, unit: 'days'),
      price: Money(wireAmount: price, currencyCode: 'EUR'),
      tags: const [],
      countryCodes: countries,
      coverImageUrl: null,
    );

final _europe = _pack(1, 'Europe 1GB', '7', ['GBR', 'FRA', 'ESP']);
final _world = _pack(2, 'World 1GB', '9', ['GBR', 'FRA', 'ESP', 'AUS', 'JPN']);
final _destinations = <Destination>[
  Destination(code: 'GBR', name: 'United Kingdom', packs: [_europe, _world]),
  Destination(code: 'FRA', name: 'France', packs: [_europe, _world]),
  Destination(code: 'ESP', name: 'Spain', packs: [_europe, _world]),
  Destination(code: 'AUS', name: 'Australia', packs: [_world]),
  Destination(code: 'JPN', name: 'Japan', packs: [_world]),
  Destination(code: 'KEN', name: 'Kenya', packs: [_pack(3, 'Kenya 1GB', '8', ['KEN'])]),
];

class _FakeCatalog implements CatalogRepository {
  @override
  Future<List<Destination>> destinations({bool refresh = false}) async => _destinations;
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
    initialLocation: '/trip',
    routes: [
      GoRoute(path: '/trip', builder: (_, _) => const TripPickerScreen()),
      GoRoute(
        path: '/trip/results',
        name: 'tripResults',
        builder: (_, s) => TripResultsScreen(codes: s.uri.queryParameters['c']!.split(',')),
      ),
    ],
  );
  tester.view.physicalSize = const Size(1170, 3000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(brand),
      sharedPreferencesProvider.overrideWithValue(prefs),
      catalogRepositoryProvider.overrideWithValue(_FakeCatalog()),
    ],
    child: MaterialApp.router(theme: buildTheme(brand), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, List<String> names) async {
  for (final n in names) {
    await tester.tap(find.text(n).last);
    await tester.pump();
  }
  await tester.tap(find.text('Voir les forfaits (${names.length})'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('one country is not a trip: the button waits for a second', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('France').last);
    await tester.pump();
    await tester.tap(find.text('Voir les forfaits (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Forfaits pour 1 pays'), findsNothing);
  });

  testWidgets('the tightest pack covering the whole trip is ranked first', (tester) async {
    await _pump(tester);
    await _choose(tester, ['Royaume-Uni', 'France']);

    expect(find.text('Forfaits pour 2 pays'), findsOneWidget);
    expect(find.text('MEILLEUR CHOIX'), findsOneWidget);
    final headlines = tester
        .widgetList<Text>(find.textContaining('Couvre vos 2 pays'))
        .map((t) => t.data)
        .toList();
    expect(headlines, ['Couvre vos 2 pays + 1 autre', 'Couvre vos 2 pays + 3 autres'],
        reason: 'Europe (3 countries) before World (5)');
  });

  testWidgets('no single pack covers the trip: said plainly, closest shown', (tester) async {
    await _pump(tester);
    await _choose(tester, ['Australie', 'Kenya']);

    expect(find.text('Aucun forfait ne couvre ces 2 pays à la fois.'), findsOneWidget);
    expect(find.text('MEILLEUR CHOIX'), findsNothing);
    expect(find.text('Couvre 1 de vos 2 pays'), findsWidgets);
    expect(find.textContaining('Manque : '), findsWidgets);
  });
}

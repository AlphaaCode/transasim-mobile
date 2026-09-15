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
import 'package:transasim_mobile/core/ui/app_button.dart';
import 'package:transasim_mobile/modules/catalog/domain/catalog.dart';
import 'package:transasim_mobile/modules/catalog/presentation/catalog_controllers.dart';
import 'package:transasim_mobile/modules/catalog/presentation/destination_screen.dart';
import 'package:transasim_mobile/modules/catalog/presentation/widgets.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_controllers.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_screens.dart';

/// eSimple's shop register, as esimple.at draws it: cyan for the fills, the
/// large title and the prices; navy for every smaller text and every button;
/// white badges with dark text. Sabily's side of the same tokens is held by
/// its goldens, which did not move.

const _cyan = Color(0xFF49CDD2);
const _navy = Color(0xFF2F3B4F);
const _white = Color(0xFFFFFFFF);

Pack _pack(int id, String name, int gb, int days) => Pack(
      id: id,
      name: name,
      description: null,
      data: DataAllowance(kilobytes: gb * 1024 * 1024, unlimited: false),
      validity: Validity(amount: days, unit: 'DAYS'),
      price: Money(wireAmount: '$gb', currencyCode: 'EUR', symbol: '€'),
      tags: const [],
      countryCodes: const ['AUT'],
      coverImageUrl: null,
    );

final _austria = Destination(code: 'AUT', name: 'Austria', packs: [
  _pack(1, 'One-off Austria 1GB', 1, 7),
  _pack(2, 'One-off Austria 5GB', 5, 30),
]);

class _Catalog implements CatalogRepository {
  @override
  Future<List<Destination>> destinations({bool refresh = false}) async => [_austria];
  @override
  Future<Destination?> destination(String code) async => _austria;
}

class _German extends LanguageController {
  @override
  String build() => 'de';
}

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style?.color;

Future<BrandConfig> _esimple() async {
  final json = jsonDecode(File('brands/esimple/brand.json').readAsStringSync());
  return BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'esimple').config as BrandConfig;
}

void main() {
  testWidgets('eSimple My eSIMs card: cyan allowance and bar, white status pill, navy top-up',
      (tester) async {
    // Checked here rather than on the device: the list needs a signed-in
    // eSimple account, and there is none to test with yet.
    final brand = await _esimple();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const plan = EsimPlan(
      id: 7,
      packName: 'One-off Austria 10GB 7 day(s)',
      countryCodes: ['AUT'],
      status: EsimStatus.active,
      dataValueKb: 10 * 1024 * 1024,
      unlimited: false,
      startingDate: null,
      endingDate: null,
      simSerial: null,
      activation: null,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(brand),
        sharedPreferencesProvider.overrideWithValue(prefs),
        allModulesProvider.overrideWithValue(const []),
        languageProvider.overrideWith(_German.new),
        esimUsageForProvider(7).overrideWithValue(
          const EsimUsage(totalData: 10, remainingData: 4, unit: 'GB'),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(brand),
        home: const Scaffold(body: SingleChildScrollView(child: EsimCard(plan: plan))),
      ),
    ));
    await tester.pump();

    expect(_textColor(tester, '10 GB'), _cyan);
    expect(_textColor(tester, 'One-off Austria 10GB 7 day(s)'), isNot(_cyan));

    final pill = tester.widget<Container>(
      find.ancestor(of: find.text('Aktiv'), matching: find.byType(Container)).first,
    );
    expect((pill.decoration! as BoxDecoration).color, _white);
    expect(_textColor(tester, 'Aktiv'), _navy);

    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect((bar.valueColor! as AlwaysStoppedAnimation<Color>).value, _cyan);

    final topUp = find.widgetWithText(AppButton, 'Aufladen');
    final fill = tester.widget<Material>(find.descendant(of: topUp, matching: find.byType(Material)).first).color;
    expect(fill, _navy, reason: 'the shop has no cyan-filled button');
  });

  testWidgets('eSimple destination: cyan fills and large type, navy text and buttons', (tester) async {
    final brand = await _esimple();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(brand),
        sharedPreferencesProvider.overrideWithValue(prefs),
        allModulesProvider.overrideWithValue(const []),
        languageProvider.overrideWith(_German.new),
        catalogRepositoryProvider.overrideWithValue(_Catalog()),
      ],
      child: MaterialApp.router(
        theme: buildTheme(brand),
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const DestinationScreen(code: 'AUT')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    // Header: a cyan gradient, white on it, a white badge with navy text.
    final header = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.gradient != null);
    expect((header.gradient! as LinearGradient).colors.first.withValues(alpha: 1), _cyan);
    expect(_textColor(tester, 'Austria'), _white);

    // Large title in cyan; pack names in navy.
    expect(_textColor(tester, 'Verfügbare Pakete'), _cyan);
    expect(_textColor(tester, 'One-off Austria 1GB'), _navy);

    // Pills are white with dark text: the header's price per GB...
    final perGb = tester.widget<Container>(
      find.ancestor(of: find.text('/ GB'), matching: find.byType(Container)).first,
    );
    expect((perGb.decoration! as BoxDecoration).color, _white);
    expect(_textColor(tester, '/ GB')!.withValues(alpha: 1), _navy);

    // ...and a pack's price tag, white with the price in cyan.
    final pill = find.byType(PricePill).first;
    final tag = tester.widget<Container>(find.descendant(of: pill, matching: find.byType(Container)).first);
    expect((tag.decoration! as BoxDecoration).color, _white);
    expect(tester.widget<Text>(find.descendant(of: pill, matching: find.byType(Text))).style?.color, _cyan);

    // The active chip is the one cyan fill with text on it; inactive chips are not.
    Color chipFill(String label) => tester
        .widget<Material>(find.ancestor(of: find.text(label).first, matching: find.byType(Material)).first)
        .color!;
    expect(chipFill('Alle'), _cyan);
    expect(_textColor(tester, 'Alle'), _white);
    expect(chipFill('7 Tage'), isNot(_cyan));

    // Every button: navy with white text. No cyan-filled button.
    for (final button in tester.widgetList<AppButton>(find.byType(AppButton))) {
      final fill = tester
          .widget<Material>(find.descendant(of: find.byWidget(button), matching: find.byType(Material)).first)
          .color;
      expect(fill, _navy, reason: button.label);
    }
    expect(find.byType(AppButton), findsNWidgets(2));
  });
}

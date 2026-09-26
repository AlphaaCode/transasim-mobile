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
          // 8 of 10 left. This test is about eSimple's cyan, so the plan is
          // deliberately a healthy one: below 50% remaining the bar is amber
          // and below 20% red, by design, and those are the brand-independent
          // semantic colours (see `usageBarColor`). Thresholds are covered in
          // test/modules/fake_esims_test.dart.
          const EsimUsage(totalData: 10, remainingData: 8, unit: 'GB'),
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
    expect(_textColor(tester, 'Österreich'), _white);

    // Large title in cyan; pack names in navy.
    expect(_textColor(tester, 'Verfügbare Pakete'), _cyan);
    expect(_textColor(tester, 'One-off Austria 1GB'), _navy);

    // Pills are white with dark text: the header's price per GB...
    final perGb = tester.widget<Container>(
      find.ancestor(of: find.text('/ GB'), matching: find.byType(Container)).first,
    );
    expect((perGb.decoration! as BoxDecoration).color, _white);
    expect(_textColor(tester, '/ GB')!.withValues(alpha: 1), _navy);

    // ...and a pack's price, in the shop's display colour on the card.
    //
    // Read off the text rather than a PricePill: the identity-card redesign
    // sets the price as plain type on the card body, so the pill is gone but
    // the palette contract it carried is not.
    // The SECOND card's price: '1,00 €' also appears in the header's
    // per-GB pill, and the first match there would be the wrong widget.
    expect(_textColor(tester, '5,00 €'), _cyan);

    // The active chip is the one cyan fill with text on it; inactive chips are not.
    //
    // Read off the AnimatedContainer, not the Material: the chip animates
    // between states now, so the fill lives on the decoration it tweens and
    // the Material above it is transparent.
    Color chipFill(String label) => ((tester
                .widget<AnimatedContainer>(find
                    .ancestor(of: find.text(label).first, matching: find.byType(AnimatedContainer))
                    .first)
                .decoration!) as BoxDecoration)
        .color!;
    expect(chipFill('Alle'), _cyan);
    expect(_textColor(tester, 'Alle'), _white);
    expect(chipFill('7 Tage'), isNot(_cyan));

    // No cyan-filled commerce button. The pack card's CTA is the fast path to
    // checkout, so it takes ShopTokens.buy — navy for eSimple — and never one
    // of the cyan fills the shop uses for its surfaces.
    //
    // The Store card's button is deliberately NOT held to this: it only
    // navigates, so it keeps the generic accent. The rule is about spending
    // money, not about being a button.
    final cta = tester.widget<Material>(
      find.ancestor(of: find.text('Auswählen').first, matching: find.byType(Material)).first,
    );
    expect(cta.color, _navy);
    expect(cta.color, isNot(_cyan));
    expect(_textColor(tester, 'Auswählen'), _white);
  });
}

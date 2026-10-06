/// The release runs the same code for both brands — asserted under eSimple's
/// OWN config, not Sabily's.
///
/// Everything shipped in 1.1.8 lives in `lib/core` or `lib/modules`, and
/// nothing in `lib/` branches on a brand slug (rule C1 forbids the name being
/// there at all). But "it must be the same" is a claim worth holding down:
/// eSimple opens in German, serves six locales rather than seven, and has the
/// wallet off, so these run the three 1.1.8 screens through that config.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/l10n.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/sync/pending_order_notice.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_controllers.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_screens.dart';

final BrandConfig _esimple = () {
  final json = jsonDecode(File('brands/esimple/brand.json').readAsStringSync());
  final r = BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'esimple');
  if (r.errors.isNotEmpty) throw StateError(r.describe('esimple'));
  return r.config as BrandConfig;
}();

EsimPlan plan({
  EsimStatus status = EsimStatus.ready,
  String? serial = '8944000000000041751',
  bool unlimited = false,
}) =>
    EsimPlan(
      id: 1,
      packName: 'Europe 3GB',
      countryCodes: const <String>['FRA'],
      status: status,
      dataValueKb: 3 * 1024 * 1024,
      unlimited: unlimited,
      startingDate: DateTime(2026, 10, 1),
      endingDate: DateTime(2099),
      simSerial: serial,
      activation: null,
    );

/// One eSIM card under eSimple's config, with whatever usage is given.
Future<void> pumpCard(
  WidgetTester tester, {
  required EsimPlan p,
  EsimUsage? usage,
  PendingOrderNotice? pending,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(_esimple),
      sharedPreferencesProvider.overrideWithValue(prefs),
      allModulesProvider.overrideWithValue(const []),
      languageProvider.overrideWith(() => _FixedLanguage('de')),
      esimPlansProvider.overrideWith((ref) async => <EsimPlan>[p]),
      esimUsageProvider.overrideWith(
        (ref) async => usage == null ? <int, EsimUsage>{} : <int, EsimUsage>{p.id: usage},
      ),
      pendingOrderNoticeProvider.overrideWithValue(pending),
    ],
    child: MaterialApp(
      theme: buildTheme(_esimple),
      locale: Locale(_esimple.defaultLocale),
      home: Scaffold(body: ListView(children: [EsimCard(plan: p)])),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eSimple is configured the way this test assumes', () {
    expect(_esimple.defaultLocale, 'de', reason: 'it opens in German, not French');
    expect(_esimple.locales, containsAll(<String>['de', 'en', 'fr', 'ar', 'sl', 'sq']));
    expect(_esimple.features.wallet, isFalse, reason: 'the wallet is off');
  });

  group('the 1.1.8 screens under eSimple', () {
    testWidgets('the usage bar draws on a READY plan, in German', (tester) async {
      // The gate used to be status == active, so this card had no bar at all.
      await pumpCard(
        tester,
        p: plan(status: EsimStatus.ready),
        usage: const EsimUsage(totalData: 3, remainingData: 3, unit: 'GB'),
      );

      final l10n = L10n(brand: _esimple, language: 'de');
      expect(find.text(l10n.t('esim.dataUsage')), findsOneWidget);
      // 0 of 3 GB used is real data from the server, drawn at zero.
      expect(find.textContaining('3 ${l10n.t('catalog.unit.gigabyte')}'), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('no usage on a non-ready plan says so instead of faking a bar',
        (tester) async {
      await pumpCard(tester, p: plan(status: EsimStatus.active), usage: null);

      final l10n = L10n(brand: _esimple, language: 'de');
      expect(find.text(l10n.t('esim.usageUnavailable')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('no usage on a READY plan shows nothing extra', (tester) async {
      await pumpCard(tester, p: plan(status: EsimStatus.ready), usage: null);

      final l10n = L10n(brand: _esimple, language: 'de');
      expect(find.text(l10n.t('esim.usageUnavailable')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Top up opens the Store, not a coming-soon sheet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final p = plan(status: EsimStatus.ready);
      var landedOnStore = false;

      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: ListView(children: [EsimCard(plan: p)])),
          routes: [
            GoRoute(
              path: 'store',
              name: 'store',
              builder: (_, _) {
                landedOnStore = true;
                return const Scaffold(body: Text('STORE'));
              },
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          brandConfigProvider.overrideWithValue(_esimple),
          sharedPreferencesProvider.overrideWithValue(prefs),
          allModulesProvider.overrideWithValue(const []),
          languageProvider.overrideWith(() => _FixedLanguage('de')),
          esimPlansProvider.overrideWith((ref) async => <EsimPlan>[p]),
          esimUsageProvider.overrideWith((ref) async =>
              <int, EsimUsage>{p.id: const EsimUsage(totalData: 3, remainingData: 3, unit: 'GB')}),
          pendingOrderNoticeProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(theme: buildTheme(_esimple), routerConfig: router),
      ));
      await tester.pumpAndSettle();

      final l10n = L10n(brand: _esimple, language: 'de');
      await tester.tap(find.text(l10n.t('esim.topUp')));
      await tester.pumpAndSettle();

      expect(landedOnStore, isTrue, reason: 'Top up is a purchase, not a "coming soon"');
      expect(find.text('STORE'), findsOneWidget);
    });

    testWidgets('an unlimited plan draws no bar and no caption', (tester) async {
      await pumpCard(
        tester,
        p: plan(status: EsimStatus.active, unlimited: true),
        usage: const EsimUsage(totalData: 0, remainingData: 0, unit: 'GB'),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('the stuck-order card under eSimple', () {
    testWidgets('it shows the reference, and leaves when the order clears',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      Widget host(PendingOrderNotice? notice) => ProviderScope(
            overrides: [
              brandConfigProvider.overrideWithValue(_esimple),
              sharedPreferencesProvider.overrideWithValue(prefs),
              allModulesProvider.overrideWithValue(const []),
              languageProvider.overrideWith(() => _FixedLanguage('de')),
              // The card lives inside the signed-in branch of the screen
              // (esim_screens.dart:103) — a signed-out visitor gets the sign-in
              // prompt and no card at all.
              isSignedInProvider.overrideWithValue(true),
              pendingOrderNoticeProvider.overrideWithValue(notice),
              esimPlansProvider.overrideWith((ref) async => <EsimPlan>[]),
              esimUsageProvider.overrideWith((ref) async => <int, EsimUsage>{}),
            ],
            child: MaterialApp.router(
              theme: buildTheme(_esimple),
              routerConfig: GoRouter(routes: [
                GoRoute(path: '/', builder: (_, _) => const MyEsimsScreen()),
                GoRoute(path: '/store', name: 'store', builder: (_, _) => const SizedBox()),
              ]),
            ),
          );

      // A real phone, not the 800x600 default: the stuck card sits above the
      // empty state, and that pair is the whole point of the card.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const PendingOrderNotice(
        reference: 'pi_ABC',
        packName: 'Europe 3GB',
        exhausted: false,
      )));
      await tester.pumpAndSettle();

      final l10n = L10n(brand: _esimple, language: 'de');
      expect(find.text(l10n.t('esim.stuck.title')), findsOneWidget);
      expect(find.textContaining('pi_ABC'), findsOneWidget);

      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();
      expect(find.text(l10n.t('esim.stuck.title')), findsNothing);
    });

    // The card sits above the empty state, and that pair wanted 201px more
    // than a landscape phone has. There is no orientation lock, so turning
    // the phone sideways on "payment received, no eSIM yet" clipped content
    // — silently in release, striped in debug.
    testWidgets('in landscape it scrolls instead of overflowing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(915, 412);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          brandConfigProvider.overrideWithValue(_esimple),
          sharedPreferencesProvider.overrideWithValue(prefs),
          allModulesProvider.overrideWithValue(const []),
          languageProvider.overrideWith(() => _FixedLanguage('de')),
          isSignedInProvider.overrideWithValue(true),
          pendingOrderNoticeProvider.overrideWithValue(const PendingOrderNotice(
            reference: 'pi_ABC',
            packName: 'Europe 3GB',
            exhausted: false,
          )),
          esimPlansProvider.overrideWith((ref) async => <EsimPlan>[]),
          esimUsageProvider.overrideWith((ref) async => <int, EsimUsage>{}),
        ],
        child: MaterialApp.router(
          theme: buildTheme(_esimple),
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const MyEsimsScreen()),
            GoRoute(path: '/store', name: 'store', builder: (_, _) => const SizedBox()),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      // pumpAndSettle would have reported a RenderFlex overflow as a test
      // failure, so reaching here is most of the assertion. The rest says the
      // card is really still on screen rather than collapsed to nothing.
      expect(tester.takeException(), isNull);
      expect(find.text(L10n(brand: _esimple, language: 'de').t('esim.stuck.title')),
          findsOneWidget);
    });

    testWidgets('portrait is unchanged: the card takes its natural height',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          brandConfigProvider.overrideWithValue(_esimple),
          sharedPreferencesProvider.overrideWithValue(prefs),
          allModulesProvider.overrideWithValue(const []),
          languageProvider.overrideWith(() => _FixedLanguage('de')),
          isSignedInProvider.overrideWithValue(true),
          pendingOrderNoticeProvider.overrideWithValue(const PendingOrderNotice(
            reference: 'pi_ABC',
            packName: 'Europe 3GB',
            exhausted: false,
          )),
          esimPlansProvider.overrideWith((ref) async => <EsimPlan>[]),
          esimUsageProvider.overrideWith((ref) async => <int, EsimUsage>{}),
        ],
        child: MaterialApp.router(
          theme: buildTheme(_esimple),
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const MyEsimsScreen()),
            GoRoute(path: '/store', name: 'store', builder: (_, _) => const SizedBox()),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      // Natural height, not a stretched half of the viewport: the Flexible
      // must be loose, or the card would grow to its share and the fix would
      // have changed what a phone in portrait shows.
      final card = tester.getSize(find.byType(SingleChildScrollView).first);
      expect(card.height, lessThan(412),
          reason: 'the card must not claim its full Flexible share');
      expect(tester.takeException(), isNull);
    });
  });
}

/// The brand's default locale, pinned. Empty preferences make the controller
/// fall back to the device locale, which is English in a test — so without
/// this the German assertions below would be testing Sabily's language.
class _FixedLanguage extends LanguageController {
  _FixedLanguage(this._value);
  final String _value;

  @override
  String build() => _value;
}

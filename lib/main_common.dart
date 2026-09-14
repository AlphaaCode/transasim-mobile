/// The single parameterised entry point. ARCHITECTURE-MOBILE.md §5.4.
///
/// Every flavor calls this with its slug and nothing else. There is one
/// `main_common.dart`, not one per client — the flavor files are one line each.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/brand/brand_loader.dart';
import 'core/brand/brand_providers.dart';
import 'core/i18n/locales.dart';
import 'core/modules/app_module.dart';
import 'core/onboarding/intro.dart';
import 'core/perf/perf_log.dart';
import 'core/router/app_router.dart';
import 'core/storage/preferences.dart';
import 'core/theme/app_theme.dart';
import 'modules/account/account_module.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modules/catalog/catalog_module.dart';
import 'modules/catalog/presentation/catalog_controllers.dart';
import 'modules/home/home_module.dart';
import 'modules/checkout/checkout_module.dart';
import 'modules/checkout/data/stripe_sheet.dart';
import 'modules/checkout/presentation/checkout_controllers.dart';
import 'modules/esim/esim_module.dart';
import 'modules/wallet/wallet_module.dart';


/// Every module the socle ships. Optional ones filter themselves out via
/// `isEnabled`; nothing here is client-specific.
const List<AppModule> kAllModules = <AppModule>[
  // Home first: it is the first tab and the first screen.
  HomeModule(),
  CatalogModule(),
  // Order matters: nav entries appear in module order, and the design puts
  // My eSIMs between the store and the profile.
  EsimModule(),
  AccountModule(),
  // No nav entry of its own — reached from a pack, never from a tab.
  CheckoutModule(),
  WalletModule(),
];

Future<void> bootstrap(String brandSlug) async {
  perfLog('bootstrap start');
  WidgetsFlutterBinding.ensureInitialized();

  final BrandResolution resolution;
  try {
    // Offline by construction. Whatever a client puts in `remoteConfigUrl`,
    // the path between process start and first frame touches the bundle and
    // SharedPreferences and nothing else.
    resolution = await BrandLoader.resolveOffline(brandSlug);
  } on BrandUnusableException catch (e) {
    // §6.3 / brief §7.7: better a loud failure than an app that starts against
    // a broken configuration and renders an empty screen.
    runApp(_ConfigErrorApp(message: e.toString()));
    return;
  }

  for (final w in resolution.warnings) {
    debugPrint('[brand:$brandSlug] warning $w');
  }
  for (final n in resolution.notices) {
    debugPrint('[brand:$brandSlug] $n');
  }

  // SharedPreferences is read once here rather than awaited inside a provider:
  // the pending-order store must be readable synchronously, because the whole
  // point of it is to be consulted the instant the app comes back.
  final prefs = await SharedPreferences.getInstance();
  // Before anything reads the language, and before a first frame could show a
  // signed-in state: an updated install starts signed out, in its language.
  await forgetLegacyApp(prefs);

  // Stripe's key is publishable by definition — it is safe in the bundle, which
  // is exactly why the config validator refuses an `sk_` one. Setting it here
  // does no network work.
  final key = resolution.config.mobile.stripePublishableKey;
  if (isUsableStripeKey(key)) {
    Stripe.publishableKey = key;
  } else {
    // A placeholder key passes the `pk_` prefix check, so the app starts and
    // would fail at the payment sheet. Checkout asks `canTakePayments` and says
    // so instead of presenting a sheet that cannot work.
    debugPrint('[brand:$brandSlug] stripePublishableKey is a placeholder; payments disabled');
  }

  runApp(_BrandHost(slug: brandSlug, initial: resolution, prefs: prefs));
}

/// Holds the configuration the app is running on, and upgrades it in place.
///
/// Startup paints from the embedded or cached config immediately. If the brand
/// declares a `remoteConfigUrl`, the fetch happens AFTER the first frame and
/// swaps the override when — and only if — it comes back valid. The user never
/// waits on it and never sees a loading screen for it; a rejected or
/// unreachable remote changes nothing at all.
class _BrandHost extends StatefulWidget {
  final String slug;
  final BrandResolution initial;
  final SharedPreferences prefs;

  const _BrandHost({required this.slug, required this.initial, required this.prefs});

  @override
  State<_BrandHost> createState() => _BrandHostState();
}

class _BrandHostState extends State<_BrandHost> {
  late BrandResolution _resolution = widget.initial;

  @override
  void initState() {
    super.initState();
    // After the first frame, never before it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_resolution.config.mobile.remoteConfigUrl == null) return;
    try {
      final next = await BrandLoader.resolve(widget.slug, fetch: fetchRemoteConfig);
      if (!mounted || next.source == _resolution.source) return;
      for (final n in next.notices) {
        debugPrint('[brand:${widget.slug}] $n');
      }
      setState(() => _resolution = next);
    } catch (e) {
      // A background refresh that fails leaves the app exactly as it was.
      debugPrint('[brand:${widget.slug}] background config refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
        // Swapping the override is what makes the upgrade reach every screen:
        // theme, strings and field list all read through these providers.
        overrides: [
          brandConfigProvider.overrideWithValue(_resolution.config),
          brandSourceProvider.overrideWithValue(_resolution.source),
          allModulesProvider.overrideWithValue(kAllModules),
          sharedPreferencesProvider.overrideWithValue(widget.prefs),
          presentSheetProvider.overrideWithValue(presentStripeSheet),
        ],
        child: const _PrefetchCatalog(child: _ResumePendingOrder(child: TransasimApp())),
      );
}

/// Starts loading the catalogue at launch, so the Store usually opens on data
/// instead of starting the 3-4 s `packs/all` wait itself.
///
/// Before the first frame and tied to nothing else — not the intro (a skipped
/// intro must not delay it), not the session (the catalogue is public). It
/// only starts the Store's own controller, so the Store shows the result, or
/// its skeleton while the load is still running, with no second request. The
/// repository serves a copy under an hour old from disk without the network.
class _PrefetchCatalog extends ConsumerStatefulWidget {
  final Widget child;
  const _PrefetchCatalog({required this.child});

  @override
  ConsumerState<_PrefetchCatalog> createState() => _PrefetchCatalogState();
}

class _PrefetchCatalogState extends ConsumerState<_PrefetchCatalog> {
  @override
  void initState() {
    super.initState();
    perfLog('catalog prefetch start');
    ref.read(catalogControllerProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Finishes an order the app was killed in the middle of.
///
/// Inside the scope, so it uses the REAL container — a detached one would read
/// a signed-out session and the retry would 401. After the first frame, for the
/// same reason nothing else at startup waits on a server.
class _ResumePendingOrder extends ConsumerStatefulWidget {
  final Widget child;
  const _ResumePendingOrder({required this.child});

  @override
  ConsumerState<_ResumePendingOrder> createState() => _ResumePendingOrderState();
}

class _ResumePendingOrderState extends ConsumerState<_ResumePendingOrder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Safe to fire blind: `/v1/subscriptions/card` keys on the Stripe intent
      // and refuses to provision a payment already COMPLETED_AND_CONSUMED.
      try {
        await resumePendingOrder(
          store: ref.read(pendingOrderStoreProvider),
          repository: ref.read(checkoutRepositoryProvider),
        );
      } catch (e) {
        debugPrint('[checkout] resume skipped: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TransasimApp extends ConsumerWidget {
  const TransasimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final language = ref.watch(languageProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: brand.mobile.displayName,
      debugShowCheckedModeBanner: false,
      theme: ref.watch(themeProvider),
      // §12.1: dark mode is explicitly OFF for every client in v1. A half-done
      // dark mode costs more than an absent one, and the decision is taken once
      // for all brands rather than drifting per screen.
      themeMode: ThemeMode.light,
      locale: Locale(language),
      supportedLocales: brand.locales.map(Locale.new),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => Directionality(
        // Arabic is exercised from the first screen, not at the end (§8.2).
        textDirection: directionFor(language),
        // Above the router, so the app loads underneath while it plays.
        child: IntroGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Shown only when the flavor's own configuration cannot be parsed. It uses no
/// brand values, because by definition there are none.
class _ConfigErrorApp extends StatelessWidget {
  final String message;
  const _ConfigErrorApp({required this.message});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Center(
              child: SingleChildScrollView(
                child: Text(message, textAlign: TextAlign.left),
              ),
            ),
          ),
        ),
      );
}

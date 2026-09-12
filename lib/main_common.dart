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
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'modules/account/account_module.dart';
import 'modules/catalog/catalog_module.dart';
import 'modules/esim/esim_module.dart';
import 'modules/wallet/wallet_module.dart';


/// Every module the socle ships. Optional ones filter themselves out via
/// `isEnabled`; nothing here is client-specific.
const List<AppModule> kAllModules = <AppModule>[
  CatalogModule(),
  // Order matters: nav entries appear in module order, and the design puts
  // My eSIMs between the store and the profile.
  EsimModule(),
  AccountModule(),
  // checkout lands here next.
  WalletModule(),
];

Future<void> bootstrap(String brandSlug) async {
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

  runApp(_BrandHost(slug: brandSlug, initial: resolution));
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

  const _BrandHost({required this.slug, required this.initial});

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
        ],
        child: const TransasimApp(),
      );
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
        child: child ?? const SizedBox.shrink(),
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

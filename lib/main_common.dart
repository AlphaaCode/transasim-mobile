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
import 'modules/wallet/wallet_module.dart';


/// Every module the socle ships. Optional ones filter themselves out via
/// `isEnabled`; nothing here is client-specific.
const List<AppModule> kAllModules = <AppModule>[
  CatalogModule(),
  AccountModule(),
  // esim and checkout land here next.
  WalletModule(),
];

Future<void> bootstrap(String brandSlug) async {
  WidgetsFlutterBinding.ensureInitialized();

  final BrandResolution resolution;
  try {
    resolution = await BrandLoader.resolve(brandSlug);
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

  runApp(
    ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(resolution.config),
        brandSourceProvider.overrideWithValue(resolution.source),
        allModulesProvider.overrideWithValue(kAllModules),
      ],
      child: const TransasimApp(),
    ),
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

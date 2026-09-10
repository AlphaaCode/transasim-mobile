/// Injection points for everything brand-derived.
///
/// ARCHITECTURE-MOBILE.md §2.10: no access to [BrandConfig] through a mutable
/// global. It is injected and overridden at the root, which is exactly what
/// makes "render this screen under two brands" a one-line test (§8.3) — and
/// what stops `if (brand == 'sabily')` from ever being convenient.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/l10n.dart';
import '../i18n/locales.dart';
import '../modules/app_module.dart';
import '../theme/app_theme.dart';
import 'brand_config.dart';
import 'brand_loader.dart';


/// Overridden at the root of the app by `bootstrap()`. Reading it without an
/// override is a programming error, and says so.
final brandConfigProvider = Provider<BrandConfig>(
  (ref) => throw UnimplementedError(
    'brandConfigProvider must be overridden in ProviderScope by bootstrap()',
  ),
);

/// How the active configuration was obtained, for the version marker (§6).
final brandSourceProvider = Provider<BrandSource>((ref) => BrandSource.embedded);

/// The full module list. Overridden by `bootstrap()` with the socle's modules;
/// tests override it with whatever they need to exercise.
final allModulesProvider = Provider<List<AppModule>>((ref) => const []);

final moduleRegistryProvider = Provider<ModuleRegistry>((ref) => ModuleRegistry(
      all: ref.watch(allModulesProvider),
      config: ref.watch(brandConfigProvider),
    ));

/// The language currently displayed.
///
/// Seeded from the brand's own `defaultLocale` — NOT from a socle constant and
/// NOT from the device. Brief §7.3: there is no universal default language;
/// eSimple serves German. A socle that assumes French is broken at the second
/// client.
class LanguageController extends Notifier<String> {
  @override
  String build() => ref.watch(brandConfigProvider).defaultLocale;

  /// Ignores a language this brand does not serve. The brand is the authority.
  void set(String language) {
    final brand = ref.watch(brandConfigProvider);
    if (!brand.locales.contains(language)) return;
    state = language;
  }
}

final languageProvider = NotifierProvider<LanguageController, String>(LanguageController.new);

final l10nProvider = Provider<L10n>((ref) => L10n(
      brand: ref.watch(brandConfigProvider),
      language: ref.watch(languageProvider),
    ));

final textDirectionProvider =
    Provider<TextDirection>((ref) => directionFor(ref.watch(languageProvider)));

/// The theme, derived from the configuration. Never written by hand.
final themeProvider = Provider((ref) => buildTheme(ref.watch(brandConfigProvider)));

final tokensProvider = Provider<AppTokens>((ref) => AppTokens.from(ref.watch(brandConfigProvider)));

/// Injection points for everything brand-derived.
///
/// ARCHITECTURE-MOBILE.md §2.10: no access to [BrandConfig] through a mutable
/// global. It is injected and overridden at the root, which is exactly what
/// makes "render this screen under two brands" a one-line test (§8.3) — and
/// what stops `if (brand == 'sabily')` from ever being convenient.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/l10n.dart';
import '../i18n/locales.dart';
import '../modules/app_module.dart';
import '../storage/preferences.dart';
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
/// Three steps, in this order:
///
///  1. **what the user chose**, if this brand still serves it. A choice
///     survives a full close — it did not once: [set] only assigned in-memory
///     state, so a killed process, or a background brand refresh rebuilding
///     this provider, came back in the default language;
///  2. **the device's language**, if this brand serves it. Someone whose phone
///     is in Arabic opens the app in Arabic, and the layout flips with it,
///     without hunting through Profile;
///  3. **English**.
///
/// Step 3 replaced `defaultLocale` on 23/09/2026, at the client's request.
/// The brand field is still validated and still has to name a served locale,
/// but it no longer decides what the app opens in: Sabily's `"fr"` was sending
/// every foreign visitor into French. English is the fallback because it is
/// the one language every one of these audiences is likeliest to read.
///
/// The brand remains the authority on what is *possible* (brief §7.3 — there
/// is no universal language, eSimple serves German). If a brand does not serve
/// English at all, its own `defaultLocale` is the last resort, because falling
/// back to a language with no dictionary would show keys.
class LanguageController extends Notifier<String> {
  static const storageKey = 'app.language';

  /// The socle's fallback once the device has been consulted. Not a brand
  /// value: a brand that serves English gets it whatever its default says.
  static const fallback = 'en';

  @override
  String build() {
    final brand = ref.watch(brandConfigProvider);
    final stored = ref.watch(sharedPreferencesProvider).getString(storageKey);
    // A language the brand has since stopped serving is not honoured.
    if (stored != null && brand.locales.contains(stored)) return stored;
    return startingLanguage(brand.locales, defaultLocale: brand.defaultLocale);
  }

  /// Ignores a language this brand does not serve. The brand is the authority.
  void set(String language) {
    if (!ref.read(brandConfigProvider).locales.contains(language)) return;
    ref.read(sharedPreferencesProvider).setString(storageKey, language);
    state = language;
  }
}

final languageProvider = NotifierProvider<LanguageController, String>(LanguageController.new);

/// The language a first launch opens in: the device's if this brand serves it,
/// else English, else the brand's own default.
///
/// [deviceLanguages] is injectable so this is testable without a platform —
/// it defaults to what the OS reports, most-preferred first, which is what
/// `PlatformDispatcher.locale` alone would miss for someone whose second
/// preference is served and whose first is not.
String startingLanguage(
  List<String> served, {
  required String defaultLocale,
  List<Locale>? deviceLanguages,
}) {
  final devices = deviceLanguages ?? PlatformDispatcher.instance.locales;
  for (final locale in devices) {
    // The language subtag only: "fr-CA", "ar-DZ" and "de-AT" are all served by
    // "fr", "ar" and "de". A brand lists languages, never regions.
    if (served.contains(locale.languageCode)) return locale.languageCode;
  }
  if (served.contains(LanguageController.fallback)) return LanguageController.fallback;
  return defaultLocale;
}

final l10nProvider = Provider<L10n>((ref) => L10n(
      brand: ref.watch(brandConfigProvider),
      language: ref.watch(languageProvider),
    ));

final textDirectionProvider =
    Provider<TextDirection>((ref) => directionFor(ref.watch(languageProvider)));

/// The theme, derived from the configuration. Never written by hand.
final themeProvider = Provider((ref) => buildTheme(ref.watch(brandConfigProvider)));

final tokensProvider = Provider<AppTokens>((ref) => AppTokens.from(ref.watch(brandConfigProvider)));

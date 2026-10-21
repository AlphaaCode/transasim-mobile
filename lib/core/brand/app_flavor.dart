/// Which of a brand's two builds is running, and the rule that keeps each on
/// its own backend (Slice H).
///
/// In October 2026 eSimple's store app was built against its DEV host, and for
/// two months its customers and payments went into the DEV database, never
/// reaching the shop's admin. A store build now talks to its brand's
/// production host or does not start; a DEV build never talks to production.
///
/// Plain Dart: Studio imports this through brand_config.dart on the Dart VM.
library;

enum AppFlavor {
  /// The store build: today's ids, the production host, nothing else.
  prod,

  /// The internal test build: ids and bundle id + ".dev", name + " DEV", the
  /// DEV host and a red banner on every screen.
  dev,
}

/// The flavor's name for Gradle, Xcode and `flutter --flavor`: the slug for
/// prod, `<slug>Dev` for dev.
String flavorName(String slug, AppFlavor flavor) => flavor == AppFlavor.prod ? slug : '${slug}Dev';

/// The host [url] names, lower-case; '' when it names none.
String hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

/// `live` or `test` for a usable Stripe publishable key, null for anything
/// else (a placeholder, a secret key, garbage).
String? stripeKeyMode(String key) =>
    RegExp(r'^pk_(test|live)_[A-Za-z0-9]{24,}$').firstMatch(key)?.group(1);

/// The key mode each flavor accepts: live for the store, test for DEV.
String stripeModeFor(AppFlavor flavor) => flavor == AppFlavor.prod ? 'live' : 'test';

/// Why a [flavor] build of [slug] whose backend is [apiBaseUrl] must not
/// start, or null when it may. [productionHosts] is the brand's own list,
/// compiled into its generated entry point from studio.json.
String? hostRefusal(String slug, AppFlavor flavor, String apiBaseUrl, List<String> productionHosts) {
  final host = hostOf(apiBaseUrl);
  final isProduction = productionHosts.contains(host);
  if (host.isEmpty) {
    return flavor == AppFlavor.prod
        ? '$slug has no production host yet: until Go prod, build the dev flavor'
        : '$slug has no DEV host: set mobile.devApiBaseUrl';
  }
  if (flavor == AppFlavor.prod && !isProduction) {
    return 'this store build talks to $host, which is not $slug\'s production host '
        '(${productionHosts.isEmpty ? 'none compiled in' : productionHosts.join(', ')})';
  }
  if (flavor == AppFlavor.dev && isProduction) {
    return 'this DEV build talks to $host, which is $slug\'s production host';
  }
  return null;
}

/// Resolves the active brand configuration. ARCHITECTURE-MOBILE.md §6.
///
///   1. REMOTE config   (fetched at start, validated, cached)  <- changeable without a store release
///   2. EMBEDDED brand.json in the flavor                      <- offline fallback, always present
///   3. Socle defaults                                         <- last net
///
/// The order is the INVERSE of the web socle's, for the reason in brief §4.3:
/// on mobile, whatever can be changed without republishing is worth a great
/// deal.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'brand_config.dart';
import 'brand_validation.dart';


/// What actually happened during resolution. Surfaced in the app's version
/// marker and in telemetry, because brief §7.7 is the rule here: *if this value
/// is wrong, does it show?* An app that starts against the wrong backend must
/// SAY so, not render an empty list.
enum BrandSource {
  /// Remote config fetched and adopted this launch.
  remote,

  /// Remote unreachable or invalid; the cached copy of a previous remote was used.
  cache,

  /// Only the config baked into the flavor was used.
  embedded,
}

class BrandResolution {
  final BrandConfig config;
  final BrandSource source;
  final List<BrandWarning> warnings;

  /// Non-fatal reasons the remote config was not adopted. Never silent.
  final List<String> notices;

  const BrandResolution({
    required this.config,
    required this.source,
    required this.warnings,
    required this.notices,
  });
}

/// Thrown only when NO usable configuration exists — the flavor itself is
/// broken. Better a loud failure than an app that serves nonsense.
class BrandUnusableException implements Exception {
  final String slug;
  final List<BrandError> errors;
  const BrandUnusableException(this.slug, this.errors);

  @override
  String toString() =>
      'brand "$slug" cannot be used:\n${errors.map((e) => '  - $e').join('\n')}';
}

typedef RemoteFetch = Future<Map<String, dynamic>?> Function(String url);

class BrandLoader {
  /// Fields the remote config may NOT change (§6.2).
  ///
  /// They are frozen in the binary — the manifest, the Info.plist, the store
  /// listing. Accepting them from the server would give the false impression
  /// they had changed.
  static const Set<String> _frozenTop = {'slug', 'name'};
  static const Set<String> _frozenMobile = {
    'applicationId',
    'bundleIdentifier',
    'displayName',
    'deepLinkScheme',
    'universalLinkHosts',
    'remoteConfigUrl',
    // §6.4: deliberately frozen. The remote config is served BY the backend it
    // would be moving — either a bootstrap paradox, or a hijack vector. A
    // backend move is rare enough to deserve a release. Dev and staging use the
    // --dart-define below instead.
    'apiBaseUrl',
  };

  /// Build-time override for the backend, so developers, CI and tests stop
  /// hitting production (`ANALYSE-EXISTANT.md` §9.3).
  ///
  /// ⚠️ It is READ here. The old CI passed two --dart-define values that
  /// `String.fromEnvironment` never read anywhere in the codebase, so they
  /// never reached the binary and nothing failed (§4.9). A value that is
  /// injected but not read is worse than no mechanism at all.
  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Build-time override for the Stripe publishable key, for the same reason
  /// and under the same rules.
  ///
  /// A brand carries ONE key, and it belongs to the client's production Stripe
  /// account. A development backend creates its PaymentIntents on a different
  /// account, and Stripe then refuses the client secret — "the publishable key
  /// used belongs to [a different] account" — which reads in the app as a
  /// declined card (seen on device 23/09/2026). Overriding the backend without
  /// being able to override the key is what made that unavoidable.
  ///
  /// Read here, for the reason given above: a define nothing reads is worse
  /// than no mechanism.
  static const String _stripeKeyOverride = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  static const String _cacheKeyPrefix = 'brand_remote_';

  /// Read `brands/<slug>/brand.json` out of the app bundle.
  static Future<Map<String, dynamic>> loadEmbedded(String slug) async {
    final raw = await rootBundle.loadString('brands/$slug/brand.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Resolution WITHOUT a network call: the embedded configuration, upgraded
  /// by a previously cached remote one if there is a valid one on disk.
  ///
  /// This is what startup uses, and it is the whole reason [resolve] takes its
  /// fetcher by injection rather than reaching for one. Nothing between process
  /// start and first frame is allowed to wait on a server: an app that opens in
  /// 80ms on a good connection and 4 seconds on a bad one is an app that feels
  /// broken exactly when the user is least able to wait.
  static Future<BrandResolution> resolveOffline(
    String slug, {
    SharedPreferences? prefs,
  }) =>
      resolve(slug, prefs: prefs);

  /// Full resolution, INCLUDING the remote fetch. Runs after first frame.
  ///
  /// [fetch] is injectable so tests drive every branch without a network.
  static Future<BrandResolution> resolve(
    String slug, {
    RemoteFetch? fetch,
    SharedPreferences? prefs,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final notices = <String>[];

    final embeddedJson = await loadEmbedded(slug);
    final embedded = BrandConfig.parse(embeddedJson, expectedSlug: slug);
    if (!embedded.isUsable) {
      // The flavor itself is broken. There is nothing to fall back to.
      throw BrandUnusableException(slug, embedded.errors);
    }

    final embeddedConfig = embedded.config as BrandConfig;
    final remoteUrl = embeddedConfig.mobile.remoteConfigUrl;

    if (remoteUrl == null) {
      notices.add('no remoteConfigUrl: running on the embedded configuration only');
      return BrandResolution(
        config: _applyBuildOverrides(embeddedConfig),
        source: BrandSource.embedded,
        warnings: embedded.warnings,
        notices: notices,
      );
    }

    final store = prefs ?? await SharedPreferences.getInstance();

    Map<String, dynamic>? remoteJson;
    var source = BrandSource.embedded;

    if (fetch != null) {
      try {
        remoteJson = await fetch(remoteUrl).timeout(timeout);
        if (remoteJson != null) source = BrandSource.remote;
      } catch (e) {
        notices.add('remote config unreachable ($e); falling back');
      }
    }

    if (remoteJson == null) {
      final cached = store.getString('$_cacheKeyPrefix$slug');
      if (cached != null) {
        try {
          remoteJson = jsonDecode(cached) as Map<String, dynamic>;
          source = BrandSource.cache;
        } catch (_) {
          notices.add('cached remote config was corrupt and has been discarded');
          await store.remove('$_cacheKeyPrefix$slug');
        }
      }
    }

    if (remoteJson == null) {
      return BrandResolution(
        config: _applyBuildOverrides(embeddedConfig),
        source: BrandSource.embedded,
        warnings: embedded.warnings,
        notices: notices,
      );
    }

    final stripped = _stripFrozen(remoteJson, notices);
    final merged = _merge(embeddedJson, stripped);
    final candidate = BrandConfig.parse(merged, expectedSlug: slug);

    if (!candidate.isUsable) {
      // §6.3: an invalid remote config is IGNORED in favour of the embedded
      // one, with a trace. A typo on the server must never break the app for
      // every user of a client.
      notices.add(
        'remote config rejected (${candidate.errors.length} error(s)): '
        '${candidate.errors.map((e) => e.field).join(', ')}',
      );
      return BrandResolution(
        config: _applyBuildOverrides(embeddedConfig),
        source: BrandSource.embedded,
        warnings: embedded.warnings,
        notices: notices,
      );
    }

    // Only cache what validated. Caching unvalidated JSON would make a bad
    // server response survive across launches.
    if (source == BrandSource.remote) {
      await store.setString('$_cacheKeyPrefix$slug', jsonEncode(remoteJson));
    }

    return BrandResolution(
      config: _applyBuildOverrides(candidate.config as BrandConfig),
      source: source,
      warnings: candidate.warnings,
      notices: notices,
    );
  }

  /// Remove the fields the remote config is not allowed to change, naming each
  /// one it tried to change.
  static Map<String, dynamic> _stripFrozen(
    Map<String, dynamic> remote,
    List<String> notices,
  ) {
    final out = Map<String, dynamic>.from(remote);
    for (final k in _frozenTop) {
      if (out.remove(k) != null) {
        notices.add('remote config tried to change "$k", which is frozen at build; ignored');
      }
    }
    final mobile = out['mobile'];
    if (mobile is Map) {
      final m = Map<String, dynamic>.from(mobile.cast<String, dynamic>());
      for (final k in _frozenMobile) {
        if (m.remove(k) != null) {
          notices.add(
              'remote config tried to change "mobile.$k", which is frozen at build; ignored');
        }
      }
      out['mobile'] = m;
    }
    return out;
  }

  /// Overlay [remote] onto [base], one level into nested objects.
  ///
  /// Deliberately shallow-per-section rather than a deep merge: a deep merge of
  /// lists and maps produces results nobody can predict from reading the two
  /// files, which is the opposite of what a configuration layer is for.
  static Map<String, dynamic> _merge(
    Map<String, dynamic> base,
    Map<String, dynamic> remote,
  ) {
    final out = Map<String, dynamic>.from(base);
    for (final entry in remote.entries) {
      final existing = out[entry.key];
      final incoming = entry.value;
      if (existing is Map && incoming is Map) {
        out[entry.key] = <String, dynamic>{
          ...existing.cast<String, dynamic>(),
          ...incoming.cast<String, dynamic>(),
        };
      } else {
        out[entry.key] = incoming;
      }
    }
    return out;
  }

  /// Apply build-time overrides that outrank everything, for dev and staging.
  ///
  /// Both overrides are applied HERE rather than at the point each value is
  /// used, because neither value has a single reader: `apiBaseUrl` is read by
  /// the network layer, and the Stripe key by both `bootstrap` (which sets
  /// `Stripe.publishableKey`) and `canTakePaymentsProvider` (which decides
  /// whether checkout offers to pay at all). Overriding at one call site would
  /// leave the other reading the brand's own value — two sources of truth for
  /// one key, which is the shape of the bug this exists to prevent.
  static BrandConfig _applyBuildOverrides(BrandConfig config) {
    if (_apiBaseUrlOverride.isEmpty && _stripeKeyOverride.isEmpty) return config;
    if (kReleaseMode) {
      // A release build must talk to the client's own backend, with the
      // client's own Stripe account, and nothing else (§10.3). Refusing here
      // means a mis-built release fails loudly.
      final overridden = [
        if (_apiBaseUrlOverride.isNotEmpty) 'API_BASE_URL',
        if (_stripeKeyOverride.isNotEmpty) 'STRIPE_PUBLISHABLE_KEY',
      ].join(' and ');
      throw StateError(
        '$overridden was overridden in a release build. '
        'Release builds must use the brand configuration.',
      );
    }
    if (_stripeKeyOverride.isNotEmpty && !_stripeKeyOverride.startsWith('pk_')) {
      // The same rule the config validator applies to brand.json (§2.9), for
      // the same reason: an `sk_` key in a bundle is an irreversible incident,
      // and an .apk decompiles. A define is not a safer place to put one.
      throw StateError(
        _stripeKeyOverride.startsWith('sk_')
            ? 'STRIPE_PUBLISHABLE_KEY is a Stripe SECRET key. It must never '
                'reach an app bundle. Use the pk_ key.'
            : 'STRIPE_PUBLISHABLE_KEY must start with "pk_".',
      );
    }
    return BrandConfig(
      slug: config.slug,
      name: config.name,
      tagline: config.tagline,
      domain: config.domain,
      colors: config.colors,
      theme: config.theme,
      logo: config.logo,
      visuals: config.visuals,
      locales: config.locales,
      defaultLocale: config.defaultLocale,
      currency: config.currency,
      features: config.features,
      support: config.support,
      legal: config.legal,
      texts: config.texts,
      // copyWith, not a field-by-field rebuild: the rebuild dropped
      // registrationSteps the day it was added, and would drop the next field
      // added too.
      // An empty define leaves the brand's own value: copyWith takes null for
      // "unchanged", so a build that overrides only one does not blank the
      // other.
      mobile: config.mobile.copyWith(
        apiBaseUrl: _apiBaseUrlOverride.isEmpty ? null : _apiBaseUrlOverride,
        stripePublishableKey: _stripeKeyOverride.isEmpty ? null : _stripeKeyOverride,
      ),
    );
  }
}

/// The real remote-config fetcher, used only by the post-first-frame refresh.
///
/// Its own Dio rather than the app's [ApiClient]: the client is built from the
/// brand configuration, and this is the call that fetches it.
Future<Map<String, dynamic>?> fetchRemoteConfig(String url) async {
  final response = await Dio().getUri<dynamic>(
    Uri.parse(url),
    options: Options(
      responseType: ResponseType.json,
      // Never throws on status; a 404 is a non-adoption, not a crash.
      validateStatus: (_) => true,
      receiveTimeout: const Duration(seconds: 6),
      sendTimeout: const Duration(seconds: 6),
    ),
  );
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) return null;
  final data = response.data;
  if (data is Map<String, dynamic>) return data;
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) return decoded;
  }
  return null;
}

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

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flavor.dart';
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
    // backend move is rare enough to deserve a release. DEV uses the dev
    // flavor, whose bundle names the DEV host (Slice H).
    'apiBaseUrl',
    'devApiBaseUrl',
  };

  /// A define that once overrode the backend in debug and profile builds. It
  /// overrides nothing now (Slice H); [refuseDefines] reads it so a build that
  /// still passes it fails loudly. The old CI passed two --dart-define values
  /// that `String.fromEnvironment` never read anywhere, so nothing failed
  /// (§4.9): a value injected but not read is worse than no mechanism.
  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// The same, for the Stripe key: the dev flavor carries its pk_test_ key.
  static const String _stripeKeyOverride = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  static const String _cacheKeyPrefix = 'brand_remote_';

  /// Read the flavor's bundle out of the app: `brands/<slug>/flavor/<flavor>.json`,
  /// which Studio generates from brand.json (Slice H). The prod one has no
  /// DEV host in it, the dev one no production host.
  static Future<Map<String, dynamic>> loadEmbedded(String slug, {AppFlavor flavor = AppFlavor.prod}) async {
    final raw = await rootBundle.loadString('brands/$slug/flavor/${flavorName(slug, flavor)}.json');
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
    AppFlavor flavor = AppFlavor.prod,
    SharedPreferences? prefs,
  }) =>
      resolve(slug, flavor: flavor, prefs: prefs);

  /// Full resolution, INCLUDING the remote fetch. Runs after first frame.
  ///
  /// [fetch] is injectable so tests drive every branch without a network.
  /// [flavor] picks the generated bundle (Slice H): the prod one carries only
  /// the production host and key, the dev one only the DEV host and key.
  static Future<BrandResolution> resolve(
    String slug, {
    AppFlavor flavor = AppFlavor.prod,
    RemoteFetch? fetch,
    SharedPreferences? prefs,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    refuseDefines();
    final notices = <String>[];

    final embeddedJson = await loadEmbedded(slug, flavor: flavor);
    final embedded = BrandConfig.parse(embeddedJson, expectedSlug: slug);
    if (!embedded.isUsable) {
      // The flavor itself is broken. There is nothing to fall back to.
      throw BrandUnusableException(slug, embedded.errors);
    }

    final embeddedConfig = embedded.config as BrandConfig;
    final remoteUrl = embeddedConfig.mobile.remoteConfigUrl;
    BrandResolution embeddedOnly() {
      final warnings = [...embedded.warnings];
      return BrandResolution(
        config: keyForFlavor(embeddedConfig, flavor, warnings),
        source: BrandSource.embedded,
        warnings: warnings,
        notices: notices,
      );
    }

    if (remoteUrl == null) {
      notices.add('no remoteConfigUrl: running on the embedded configuration only');
      return embeddedOnly();
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

    if (remoteJson == null) return embeddedOnly();

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
      return embeddedOnly();
    }

    // Only cache what validated. Caching unvalidated JSON would make a bad
    // server response survive across launches.
    if (source == BrandSource.remote) {
      await store.setString('$_cacheKeyPrefix$slug', jsonEncode(remoteJson));
    }

    final warnings = [...candidate.warnings];
    var config = candidate.config as BrandConfig;
    // A key from the server counts only in this flavor's mode (Slice H): a
    // pk_test_ key must not turn a store build's payments into test ones, nor
    // a pk_live_ key make a DEV build charge real cards.
    final sent = config.mobile.stripePublishableKey;
    final mine = embeddedConfig.mobile.stripePublishableKey;
    if (sent != mine && stripeKeyMode(sent) != stripeModeFor(flavor)) {
      warnings.add(BrandWarning('mobile.stripePublishableKey',
          'remote config sent a ${stripeKeyMode(sent) ?? 'unusable'} key to a ${flavor.name} build; the built-in key stays'));
      config = config.withMobile(config.mobile.copyWith(stripePublishableKey: mine));
    }

    return BrandResolution(
      config: keyForFlavor(config, flavor, warnings),
      source: source,
      warnings: warnings,
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

  /// The second lock behind the flavors (Slice H). `API_BASE_URL` and
  /// `STRIPE_PUBLISHABLE_KEY` used to override the brand's backend and key in
  /// debug and profile builds; the dev flavor now carries the DEV host and key
  /// instead, and no build mode overrides either. Still READ, so a build that
  /// passes one fails at once, in every mode, rather than silently ignoring it:
  /// a define nothing reads is worse than no mechanism (§4.9).
  static void refuseDefines() {
    final passed = [
      if (_apiBaseUrlOverride.isNotEmpty) 'API_BASE_URL',
      if (_stripeKeyOverride.isNotEmpty) 'STRIPE_PUBLISHABLE_KEY',
    ];
    if (passed.isEmpty) return;
    throw StateError(
      '${passed.join(' and ')} was passed to this build. No build overrides the '
      'brand\'s backend or Stripe key any more: build the dev flavor '
      '(flutter build … --flavor <slug>Dev) for the DEV server.',
    );
  }

  /// [config] with its Stripe key dropped when it is not of [flavor]'s mode:
  /// a store build takes only `pk_live_`, a DEV build only `pk_test_`. Dropped
  /// means payments off, said in [warnings], never a sheet charging the wrong
  /// account.
  static BrandConfig keyForFlavor(BrandConfig config, AppFlavor flavor, List<BrandWarning> warnings) {
    final key = config.mobile.stripePublishableKey;
    final mode = stripeKeyMode(key);
    if (mode == null || mode == stripeModeFor(flavor)) return config;
    warnings.add(BrandWarning('mobile.stripePublishableKey',
        'a pk_${mode}_ key in a ${flavor.name} build: payments are off (it takes only pk_${stripeModeFor(flavor)}_)'));
    return config.withMobile(config.mobile.copyWith(stripePublishableKey: 'pk_off_wrong_mode'));
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

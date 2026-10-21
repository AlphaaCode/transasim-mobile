/// Slice H: a store or TestFlight build never talks to a DEV server.
///
/// In October 2026 eSimple's store app was built against its DEV host, and for
/// two months its customers and payments went into the DEV database, never
/// reaching the shop's admin. So:
///
/// - brand.json holds both hosts: `mobile.apiBaseUrl`, the PRODUCTION one, and
///   `mobile.devApiBaseUrl`, the DEV one. Each flavor ships a bundle generated
///   from it with only its own (`brands/<slug>/flavor/<flavor>.json`).
/// - studio.json `production` pins the production host, frozen like a
///   published package id:
///   - `apiBaseUrl`: the pinned URL. Only Go prod's Apply writes it into
///     brand.json; changing the pin is its own logged action
///     (`studio --pin-production`).
///   - `aliases`: other names of the same production server. Never written
///     into brand.json, never accepted as a DEV host.
///   - `exception`: `{apiBaseUrl, reason}`, a temporary production host that
///     store builds use instead (eSimple's DEV server, until the server
///     merge). Red at every release, which must acknowledge it.
///   - `log`: every pin, exception and Go prod, with its time and reason.
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../gen_brand_flavors.dart' show brandSlugs, devFlavorEnabled;

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

Map<String, dynamic> _json(String path) {
  final f = File(path);
  return f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : {};
}

/// studio.json's `production` block.
Map<String, dynamic> productionOf(Map studio) => _map(studio['production']);

/// The pinned production URL, '' before Go prod has pinned one.
String pinnedApiBaseUrl(Map studio) => '${productionOf(studio)['apiBaseUrl'] ?? ''}';

/// The standing exception, or null.
({String apiBaseUrl, String reason})? productionException(Map studio) {
  final e = productionOf(studio)['exception'];
  if (e is! Map || e['apiBaseUrl'] is! String) return null;
  return (apiBaseUrl: e['apiBaseUrl'] as String, reason: '${e['reason'] ?? ''}');
}

/// What brand.json's `mobile.apiBaseUrl` must hold: the exception's URL while
/// one stands, else the pinned one, else nothing (before Go prod).
String expectedApiBaseUrl(Map studio) => productionException(studio)?.apiBaseUrl ?? pinnedApiBaseUrl(studio);

/// The production hosts pinned for good: the pinned host and its aliases.
Set<String> pinnedHosts(Map studio) => {
      hostOf(pinnedApiBaseUrl(studio)),
      for (final a in (productionOf(studio)['aliases'] as List? ?? const [])) '$a'.toLowerCase(),
    }..remove('');

/// Every host a store build of the brand may talk to, compiled into its
/// generated entry points: the pinned host, its aliases, the exception's.
List<String> productionHosts(Map studio) => {
      ...pinnedHosts(studio),
      if (productionException(studio) case final e?) hostOf(e.apiBaseUrl),
    }.where((h) => h.isNotEmpty).toList();

/// Every DEV host Studio knows, host -> the brand it is DEV for: each brand's
/// `mobile.devApiBaseUrl` and its Backend tab's DEV backend. No store artifact
/// may name one, a standing exception aside.
Map<String, String> devHosts(String root) => {
      for (final slug in brandSlugs(root))
        for (final h in [
          hostOf('${_map(_json('$root/brands/$slug/brand.json')['mobile'])['devApiBaseUrl'] ?? ''}'),
          '${_map(_map(_json('$root/brands/$slug/studio.json')['backend'])['dev'])['domain'] ?? ''}'.toLowerCase(),
          hostOf('${_map(_map(_json('$root/brands/$slug/studio.json')['backend'])['dev'])['apiBaseUrl'] ?? ''}'),
        ])
          if (h.isNotEmpty) h: slug,
    };

/// Every host of every brand, production and DEV: what a scan needs to tell
/// a DEV host such as `dev.example.com` on its own from the tail of `api.dev.example.com`.
Set<String> knownHosts(String root) => {
      ...devHosts(root).keys,
      for (final slug in brandSlugs(root)) ...productionHosts(_json('$root/brands/$slug/studio.json')),
    };

/// brand.json's fields only the dev flavor reads.
const devOnlyFields = ['devApiBaseUrl', 'devStripePublishableKey', 'devGoogleIosClientId'];

/// The bundle a flavor ships, generated from [brand]. The prod one is brand.json
/// without a DEV value; the dev one has the DEV host and key as its own, ids and
/// bundle id + ".dev", name + " DEV", its own iOS Google client (or none), and
/// no remote config, which production serves.
Map<String, dynamic> flavorBundle(Map<String, dynamic> brand, AppFlavor flavor) {
  final copy = jsonDecode(jsonEncode(brand)) as Map<String, dynamic>;
  final mobile = _map(copy['mobile']);
  if (flavor == AppFlavor.dev) {
    mobile['apiBaseUrl'] = mobile['devApiBaseUrl'];
    mobile['stripePublishableKey'] = mobile['devStripePublishableKey'] ?? 'pk_test_PLACEHOLDER_AWAITING_CLIENT';
    for (final id in ['applicationId', 'bundleIdentifier']) {
      mobile[id] = '${mobile[id]}.dev';
    }
    mobile['displayName'] = '${mobile['displayName']} DEV';
    mobile.remove('remoteConfigUrl');
    if (mobile['devGoogleIosClientId'] case final String client) {
      mobile['googleIosClientId'] = client;
    } else {
      mobile.remove('googleIosClientId');
    }
  }
  for (final f in devOnlyFields) {
    mobile.remove(f);
  }
  copy['mobile'] = mobile;
  return copy;
}

/// Why [slug] has no dev flavor, or null when it has one.
String? devFlavorRefusal(String slug, Map<String, dynamic> brand, Map studio) {
  if (devFlavorEnabled(brand)) return null;
  if ('${_map(brand['mobile'])['devApiBaseUrl'] ?? ''}'.isEmpty) {
    return '$slug has no DEV host: set mobile.devApiBaseUrl in the Brand tab';
  }
  final e = productionException(studio);
  return e != null
      ? "$slug's DEV server is its production today (${e.reason}): no DEV build until that ends"
      : "$slug's DEV host is its production host: no DEV build";
}

/// Studio's host rules on [brand], beyond the app's own parser: field, reason.
List<(String, String)> hostErrors(String root, String slug, Map<String, dynamic> brand, Map studio) {
  final mobile = _map(brand['mobile']);
  final dev = hostOf('${mobile['devApiBaseUrl'] ?? ''}');
  return [
    if (dev.isNotEmpty)
      for (final other in {...brandSlugs(root), slug})
        if (pinnedHosts(other == slug ? studio : _json('$root/brands/$other/studio.json')).contains(dev))
          ('mobile.devApiBaseUrl', "$dev is $other's production: never a DEV host"),
    if (stripeKeyMode('${mobile['stripePublishableKey'] ?? ''}') == 'test')
      ('mobile.stripePublishableKey', 'a store build takes only a pk_live_ key, or none with payments off: a pk_test_ key goes in mobile.devStripePublishableKey'),
  ];
}

/// One entry of studio.json `production.log`.
Map<String, Object?> logEntry(String action, String apiBaseUrl, {String? reason, required DateTime now}) => {
      'at': now.toUtc().toIso8601String(),
      'action': action,
      'apiBaseUrl': apiBaseUrl,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };

/// [studio] after the explicit, logged change of the pin: the production URL,
/// and the exception set or ended. brand.json is left as it is: Go prod's
/// Apply then writes the new value into it.
Map<String, dynamic> repinned(Map<String, dynamic> studio,
    {required String apiBaseUrl, required String reason, String? exceptionUrl, bool endException = false, required DateTime now}) {
  for (final url in [apiBaseUrl, ?exceptionUrl]) {
    if (!url.startsWith('https://') || hostOf(url).isEmpty) {
      throw ArgumentError('a production URL is https://<host>/…, not "$url"');
    }
  }
  if (reason.trim().isEmpty) throw ArgumentError('a pin change says why: --reason "<why>"');
  final production = {...productionOf(studio)};
  final log = [...(production['log'] as List? ?? const [])];
  if (pinnedApiBaseUrl(studio) != apiBaseUrl) log.add(logEntry('pinned', apiBaseUrl, reason: reason, now: now));
  production['apiBaseUrl'] = apiBaseUrl;
  if (exceptionUrl != null) {
    production['exception'] = {'apiBaseUrl': exceptionUrl, 'reason': reason};
    log.add(logEntry('exception set', exceptionUrl, reason: reason, now: now));
  } else if (endException && production.remove('exception') != null) {
    log.add(logEntry('exception ended', apiBaseUrl, reason: reason, now: now));
  }
  production['log'] = log;
  return {...studio, 'production': production};
}

// ---- probes ------------------------------------------------------------------

/// What an HTTPS connection to a host says of its certificate.
typedef TlsProbe = ({String host, bool ok, int? daysLeft, String detail});

/// Opens [host]:443, the chain checked against the trusted roots, and returns
/// when its certificate ends (null: none). An invalid chain throws.
Future<DateTime?> certificateEnd(String host, {Duration timeout = const Duration(seconds: 8)}) async {
  final socket = await SecureSocket.connect(host, 443, timeout: timeout);
  final end = socket.peerCertificate?.endValidity;
  socket.destroy();
  return end;
}

/// [host]'s HTTPS certificate: OK when the chain is valid and more than 14
/// days remain. [certificate] is injectable, so tests never touch a server.
Future<TlsProbe> probeTls(String host,
    {Future<DateTime?> Function(String host)? certificate, DateTime Function() clock = DateTime.now}) async {
  try {
    final end = await (certificate ?? certificateEnd)(host);
    if (end == null) return (host: host, ok: false, daysLeft: null, detail: 'no certificate');
    final days = end.difference(clock()).inDays;
    return (
      host: host,
      ok: days > 14,
      daysLeft: days,
      detail: days > 14 ? 'valid certificate, $days days left' : 'the certificate ends in $days days: renew it',
    );
  } on HandshakeException catch (e) {
    return (host: host, ok: false, daysLeft: null, detail: 'certificate not valid: ${e.message}');
  } on Object catch (e) {
    return (host: host, ok: false, daysLeft: null, detail: 'no HTTPS answer: $e');
  }
}

/// Each brand's hosts, for Integrations and Doctor: production (pinned, its
/// aliases, a standing exception) then DEV.
List<({String slug, String env, String host, String note})> brandHosts(String root) => [
      for (final slug in brandSlugs(root))
        ...() {
          final studio = _json('$root/brands/$slug/studio.json');
          final brand = _json('$root/brands/$slug/brand.json');
          final pinned = hostOf(pinnedApiBaseUrl(studio));
          final e = productionException(studio);
          final dev = hostOf('${_map(brand['mobile'])['devApiBaseUrl'] ?? ''}');
          return [
            if (pinned.isNotEmpty) (slug: slug, env: 'production', host: pinned, note: e == null ? 'pinned' : 'pinned, after the exception ends'),
            for (final a in pinnedHosts(studio).difference({pinned})) (slug: slug, env: 'production', host: a, note: 'alias'),
            if (e != null) (slug: slug, env: 'production', host: hostOf(e.apiBaseUrl), note: 'EXCEPTION: ${e.reason}'),
            if (dev.isNotEmpty) (slug: slug, env: 'dev', host: dev, note: devFlavorRefusal(slug, brand, studio) ?? 'the dev flavor'),
          ];
        }(),
    ];

/// [brandHosts] (of [slug] only, when given) with an HTTPS probe of each
/// host, all at once.
Future<List<Map<String, Object?>>> probeBrandHosts(String root,
    {String? slug, Future<TlsProbe> Function(String host)? probe}) async {
  final rows = [for (final r in brandHosts(root)) if (slug == null || r.slug == slug) r];
  final hosts = {for (final r in rows) r.host};
  final probes = {
    for (final p in await Future.wait([for (final h in hosts) (probe ?? probeTls)(h)])) p.host: p,
  };
  return [
    for (final r in rows)
      {
        'slug': r.slug,
        'env': r.env,
        'host': r.host,
        'note': r.note,
        'ok': probes[r.host]!.ok,
        'daysLeft': probes[r.host]!.daysLeft,
        'detail': probes[r.host]!.detail,
      },
  ];
}

/// The flavor's entry point, as `flutter … -t` takes it.
String entryPoint(String slug, AppFlavor flavor) => 'lib/flavors/main_$slug${flavor == AppFlavor.dev ? '_dev' : ''}.dart';

/// Why no store build of [slug] may start now, from brand.json and studio.json
/// alone, for every brand, legacy ones included; empty when it may. The built
/// artifact is checked again, byte by byte, by `studio --verify-release` and
/// `--verify-ipa`. [acknowledged]: this release accepted the standing
/// production exception.
List<String> hostReleaseRefusal(String root, String slug, {bool acknowledged = false}) {
  final studio = _json('$root/brands/$slug/studio.json');
  final brand = _json('$root/brands/$slug/brand.json');
  final url = '${_map(brand['mobile'])['apiBaseUrl'] ?? ''}';
  final expected = expectedApiBaseUrl(studio);
  final e = productionException(studio);
  return [
    if (pinnedApiBaseUrl(studio).isEmpty)
      'store-build-on-dev: no production host is pinned yet, and brand.json says ${url.isEmpty ? 'none' : url}: Go prod first'
    else if (url != expected)
      'store-build-on-dev: brand.json apiBaseUrl is ${url.isEmpty ? 'empty' : url}, not the pinned $expected: press Go prod',
    for (final (_, why) in hostErrors(root, slug, brand, studio)) 'store-build-on-dev: $why',
    if (e != null && !acknowledged)
      'store-build-on-dev: PRODUCTION EXCEPTION, ${hostOf(e.apiBaseUrl)}: ${e.reason}. Acknowledge it for this release',
  ];
}

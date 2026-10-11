/// Studio's own probes (docs/STUDIO-SPEC.md §16.5): calls from this PC to a
/// brand's public endpoints, run when Alpha presses Check. They read what
/// anyone on the internet can, and nothing else: no server is logged into.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef Lookup = Future<List<InternetAddress>> Function(String host);

/// The probes for one backend, by name, each `{status, ...}` or `{error}`.
/// [httpsBase] and [httpBase] default to the domain; tests point them at a
/// local server, with [client] trusting its certificate and [clock] moved.
Future<Map<String, Object?>> runProbes({
  required String domain,
  required String apiBaseUrl,
  required bool google,
  required bool ios,
  String? httpsBase,
  String? httpBase,
  HttpClient Function()? client,
  Lookup? lookup,
  DateTime Function()? clock,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final now = clock ?? DateTime.now;
  final https = httpsBase ?? 'https://$domain';
  final http = httpBase ?? 'http://$domain';

  Future<Map<String, Object?>> call(String url,
      {String method = 'GET', Object? json, bool follow = true, bool count = false, bool cert = false}) async {
    final c = (client ?? HttpClient.new)()..connectionTimeout = timeout;
    final watch = Stopwatch()..start();
    try {
      final req = await c.openUrl(method, Uri.parse(url)).timeout(timeout);
      req.followRedirects = follow;
      req.headers.set('user-agent', 'SPC Studio probe');
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      }
      final res = await req.close().timeout(timeout);
      final ttfb = watch.elapsedMilliseconds;
      final out = <String, Object?>{'status': res.statusCode, 'ttfbMs': ttfb};
      if (cert && res.certificate != null) {
        out['daysLeft'] = res.certificate!.endValidity.difference(now()).inDays;
      }
      if (count) {
        final body = await utf8.decodeStream(res).timeout(timeout * 4);
        final decoded = res.statusCode == 200 ? jsonDecode(body) : null;
        // /v1/packs/all is a Page: {content: [...]}.
        final list = decoded is Map ? decoded['content'] : decoded;
        out['count'] = list is List ? list.length : 0;
      } else {
        await res.drain<void>();
      }
      return out;
    } on HandshakeException catch (e) {
      return {'error': 'TLS handshake failed: ${e.osError?.message ?? e.message}'};
    } on TimeoutException {
      return {'error': 'no answer within ${timeout.inSeconds} s'};
    } on SocketException catch (e) {
      return {'error': e.osError?.message ?? e.message};
    } on FormatException {
      return {'error': 'the answer is not JSON'};
    } on HttpException catch (e) {
      return {'error': e.message};
    } finally {
      c.close(force: true);
    }
  }

  Future<Map<String, Object?>> dns() async {
    try {
      final found = await (lookup ?? (h) => InternetAddress.lookup(h, type: InternetAddressType.IPv4))(domain)
          .timeout(timeout);
      return {'addresses': [for (final a in found) a.address]};
    } on SocketException catch (e) {
      return {'error': e.osError?.message ?? e.message};
    } on TimeoutException {
      return {'error': 'no answer within ${timeout.inSeconds} s'};
    }
  }

  // Health is never probed publicly: nginx denies /management on purpose, and
  // the report's local health is the authority. This call checks that it
  // stays denied, and reads the certificate on the way.
  final mgmt = await call('$https/management/health', cert: true);
  final junk = {'idToken': 'spc-studio-probe-not-a-token'};
  final results = await Future.wait([
    dns(),
    call('$http/management/health', follow: false),
    call('$apiBaseUrl/v1/packs/all', count: true),
    call('$apiBaseUrl/app-config'),
    if (google) call('$apiBaseUrl/v1/auth/google', method: 'POST', json: junk),
    if (ios) call('$apiBaseUrl/v1/auth/apple', method: 'POST', json: junk),
  ]);
  return {
    'at': now().toUtc().toIso8601String(),
    'dns': results[0],
    'tls': mgmt['error'] != null
        ? {'error': mgmt['error']}
        : mgmt['daysLeft'] == null
            ? {'error': 'no certificate seen'}
            : {'daysLeft': mgmt['daysLeft']},
    'mgmtHttps': mgmt,
    'mgmtHttp': results[1],
    'packs': results[2],
    'appConfig': results[3],
    if (google) 'authGoogle': results[4],
    if (ios) 'authApple': results[google ? 5 : 4],
  };
}

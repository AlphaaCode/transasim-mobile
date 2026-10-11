@Timeout(Duration(minutes: 1))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/probes.dart';

/// Studio's probes (docs/STUDIO-SPEC.md §16.5) against a local fake backend:
/// HTTPS with a certificate made for this run (never committed), and plain
/// HTTP that redirects. The clock is moved to read the certificate's days.
void main() {
  String? openssl;
  late Directory dir;
  late HttpServer secure, plain;
  var appleStatus = 400;
  var plainManagement = 301;

  setUpAll(() async {
    // flutter test answers every HttpClient request with 400; these probes
    // need the real thing, against a server on this machine.
    HttpOverrides.global = null;
    for (final candidate in [
      'openssl',
      r'C:\Program Files\Git\usr\bin\openssl.exe',
      r'C:\Program Files\Git\mingw64\bin\openssl.exe',
    ]) {
      try {
        if ((await Process.run(candidate, ['version'])).exitCode == 0) {
          openssl = candidate;
          break;
        }
      } on ProcessException {
        continue;
      }
    }
    if (openssl == null) return;
    dir = Directory.systemTemp.createTempSync('probes');
    final made = await Process.run(openssl!, [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '30', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost', '-keyout', '${dir.path}/key.pem', '-out', '${dir.path}/cert.pem',
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final context = SecurityContext()
      ..useCertificateChain('${dir.path}/cert.pem')
      ..usePrivateKey('${dir.path}/key.pem');
    secure = await HttpServer.bindSecure('localhost', 0, context);
    secure.listen((req) async {
      final res = req.response;
      switch (req.uri.path) {
        case '/management/health':
          res.statusCode = 403;
        case '/api/v1/packs/all':
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'content': [{}, {}, {}]}));
        case '/api/v1/auth/google':
          final body = jsonDecode(await utf8.decodeStream(req)) as Map;
          res.statusCode = body['idToken'] is String ? 400 : 500;
        case '/api/v1/auth/apple':
          res.statusCode = appleStatus;
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
    plain = await HttpServer.bind('localhost', 0);
    plain.listen((req) async {
      req.response.statusCode = plainManagement;
      if (plainManagement == 301) req.response.headers.set('location', 'https://localhost:${secure.port}/');
      await req.response.close();
    });
  });

  tearDownAll(() async {
    if (openssl == null) return;
    await secure.close(force: true);
    await plain.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> probe({DateTime? at}) => runProbes(
        domain: 'acorn.transasim.com',
        apiBaseUrl: 'https://localhost:${secure.port}/api',
        httpsBase: 'https://localhost:${secure.port}',
        httpBase: 'http://localhost:${plain.port}',
        google: true,
        ios: true,
        client: () => HttpClient(context: SecurityContext()..setTrustedCertificates('${dir.path}/cert.pem')),
        lookup: (_) async => [InternetAddress('169.58.35.140')],
        clock: at == null ? null : () => at,
      );

  test('a healthy backend: packs counted, management denied, junk tokens refused, days read', () async {
    if (openssl == null) return markTestSkipped('openssl not found: cannot make a test certificate');
    final p = await probe();
    expect(p['dns'], {'addresses': ['169.58.35.140']});
    expect((p['tls'] as Map)['daysLeft'], inInclusiveRange(28, 30));
    expect((p['mgmtHttps'] as Map)['status'], 403);
    expect((p['mgmtHttp'] as Map)['status'], 301, reason: 'a redirect is not followed');
    expect(p['packs'], allOf(containsPair('status', 200), containsPair('count', 3)));
    expect((p['packs'] as Map)['ttfbMs'], isA<int>());
    expect((p['authGoogle'] as Map)['status'], 400);
    expect((p['authApple'] as Map)['status'], 400);
    expect((p['appConfig'] as Map)['status'], 404);
  });

  test('the certificate days follow the clock', () async {
    if (openssl == null) return markTestSkipped('openssl not found');
    final p = await probe(at: DateTime.now().add(const Duration(days: 20)));
    expect((p['tls'] as Map)['daysLeft'], inInclusiveRange(8, 10));
  });

  test('what a broken backend looks like to the probes', () async {
    if (openssl == null) return markTestSkipped('openssl not found');
    appleStatus = 404;
    plainManagement = 200;
    addTearDown(() {
      appleStatus = 400;
      plainManagement = 301;
    });
    final p = await probe();
    expect((p['authApple'] as Map)['status'], 404);
    expect((p['mgmtHttp'] as Map)['status'], 200);
  });

  test('an untrusted certificate is a TLS error, and an unknown host a DNS error', () async {
    if (openssl == null) return markTestSkipped('openssl not found');
    final p = await runProbes(
      domain: 'no-such-host.invalid',
      apiBaseUrl: 'https://localhost:${secure.port}/api',
      httpsBase: 'https://localhost:${secure.port}',
      httpBase: 'http://localhost:${plain.port}',
      google: false,
      ios: false,
      timeout: const Duration(seconds: 3),
    );
    expect((p['tls'] as Map)['error'], contains('TLS'));
    expect((p['dns'] as Map)['error'], isNotNull);
    expect(p.containsKey('authGoogle'), isFalse);
  });
}

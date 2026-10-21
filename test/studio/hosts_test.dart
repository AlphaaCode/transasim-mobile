import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../tool/gen_brand_flavors.dart' show devFlavorEnabled;
import '../../tool/studio/src/doctor.dart' show hostChecks;
import '../../tool/studio/src/generate.dart' show readStudio;
import '../../tool/studio/src/hosts.dart';
import 'esimple_on_exception.dart';

/// Slice H's model in Studio: the pin, its exception and log, each flavor's
/// bundle, the host rules and the HTTPS probes. No test here reaches a server.
void main() {
  final now = DateTime.utc(2026, 10, 21, 9);
  Map<String, dynamic> brand(String slug) =>
      jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

  group('the pin moves only on purpose, and says why', () {
    test('a new pin, an exception set, then ended: each a line in the log', () {
      var s = repinned(const {}, apiBaseUrl: 'https://api.example.com/api', reason: 'first', now: now);
      expect(pinnedApiBaseUrl(s), 'https://api.example.com/api');
      s = repinned(s,
          apiBaseUrl: 'https://api.example.com/api', reason: 'until the merge', exceptionUrl: 'https://dev.example.com/api', now: now);
      expect(expectedApiBaseUrl(s), 'https://dev.example.com/api');
      s = repinned(s, apiBaseUrl: 'https://api.example.com/api', reason: 'merged', endException: true, now: now);
      expect(expectedApiBaseUrl(s), 'https://api.example.com/api');
      expect([for (final e in productionOf(s)['log'] as List) '${(e as Map)['action']}: ${e['reason']}'],
          ['pinned: first', 'exception set: until the merge', 'exception ended: merged']);
    });

    test('a pin is https with a host, and always has a reason', () {
      expect(() => repinned(const {}, apiBaseUrl: 'http://api.example.com/api', reason: 'x', now: now), throwsArgumentError);
      expect(() => repinned(const {}, apiBaseUrl: 'https://api.example.com/api', reason: ' ', now: now), throwsArgumentError);
    });
  });

  group('each flavor ships its own bundle', () {
    test("the store bundle is brand.json without a DEV value", () {
      final b = flavorBundle(brand('acorn'), AppFlavor.prod)['mobile'] as Map;
      expect(b['apiBaseUrl'], 'https://acorn-api.transasim.com/api');
      for (final f in devOnlyFields) {
        expect(b.containsKey(f), isFalse, reason: f);
      }
    });

    test('the DEV bundle: the DEV host and key, ids + .dev, name + DEV, no remote config, its own iOS client', () {
      final b = flavorBundle(brand('sabily'), AppFlavor.dev)['mobile'] as Map;
      expect(b['apiBaseUrl'], 'https://api.sabily.transasim.com/api');
      expect(b['applicationId'], 'com.sabily.esim.dev');
      expect(b['bundleIdentifier'], 'com.sabily.esim.dev');
      expect(b['displayName'], 'Sabily DEV');
      expect(b.containsKey('remoteConfigUrl'), isFalse);
      expect(b.containsKey('googleIosClientId'), isFalse, reason: "the store app's client names the store bundle id");
      expect(stripeKeyMode('${b['stripePublishableKey']}'), isNot('live'));
    });

    test('eSimple has a DEV build now that its DEV server is no longer its production', () {
      expect(devFlavorEnabled(brand('esimple')), isTrue);
      expect(devFlavorRefusal('esimple', brand('esimple'), readStudio('.', 'esimple')), isNull);
      expect(devFlavorEnabled(brand('acorn')), isTrue);
    });

    test('a brand whose DEV server stands in for production has no DEV build, and says why', () {
      final onException = brandOnException(brand('esimple'));
      expect(devFlavorEnabled(onException), isFalse);
      expect(devFlavorRefusal('esimple', onException, studioOnException(readStudio('.', 'esimple'))),
          contains('DEV server serving as production until the merge'));
    });
  });

  group("Studio's host rules", () {
    test('a production host, or its alias, is never a DEV host', () {
      for (final dev in ['https://acorn-api.transasim.com/api', 'https://api.esimple.transasim.com/api', 'https://api.sabily.fr/api']) {
        final b = brand('acorn');
        (b['mobile'] as Map)['devApiBaseUrl'] = dev;
        expect(hostErrors('.', 'acorn', b, readStudio('.', 'acorn')).map((e) => e.$1), contains('mobile.devApiBaseUrl'), reason: dev);
      }
      expect(hostErrors('.', 'acorn', brand('acorn'), readStudio('.', 'acorn')), isEmpty);
    });

    test('a pk_test_ key never sits in the store build\'s field', () {
      final b = brand('acorn');
      (b['mobile'] as Map)['stripePublishableKey'] = 'pk_test_${'a' * 30}';
      expect(hostErrors('.', 'acorn', b, readStudio('.', 'acorn')).map((e) => e.$1), contains('mobile.stripePublishableKey'));
    });

    test('every brand\'s hosts are listed: eSimple production and its alias, its DEV host apart', () {
      final rows = brandHosts('.');
      expect([for (final r in rows) if (r.slug == 'esimple') '${r.env} ${r.host}'],
          ['production api.esimple.at', 'production api.esimple.transasim.com', 'dev esimple.transasim.com']);
      expect(rows.where((r) => r.note.contains('EXCEPTION')), isEmpty, reason: 'no brand stands on one');
    });

    test('a standing exception is listed, and named', () {
      final copy = copyOfBrandFiles();
      addTearDown(() => copy.deleteSync(recursive: true));
      putEsimpleOnException(copy.path);
      final rows = brandHosts(copy.path);
      expect([for (final r in rows) if (r.slug == 'esimple') '${r.env} ${r.host}'],
          ['production api.esimple.at', 'production api.esimple.transasim.com', 'production esimple.transasim.com', 'dev esimple.transasim.com']);
      expect(rows.firstWhere((r) => r.slug == 'esimple' && r.env == 'production' && r.host == 'esimple.transasim.com').note,
          contains('EXCEPTION'));
    });
  });

  group('the HTTPS probe', () {
    test('a valid certificate with more than 14 days left is OK; fewer, a broken chain or no answer is not', () async {
      Future<TlsProbe> probe(Future<DateTime?> Function(String) cert) => probeTls('x.example', certificate: cert, clock: () => now);
      expect((await probe((_) async => now.add(const Duration(days: 30)))).ok, isTrue);
      final soon = await probe((_) async => now.add(const Duration(days: 10)));
      expect((soon.ok, soon.daysLeft), (false, 10));
      final broken = await probe((_) async => throw const HandshakeException('CERTIFICATE_VERIFY_FAILED'));
      expect(broken.ok, isFalse);
      expect(broken.detail, contains('not valid'));
      expect((await probe((_) async => throw const SocketException('refused'))).detail, contains('no HTTPS answer'));
      expect((await probe((_) async => null)).ok, isFalse);
    });

    test('Doctor lists every brand\'s hosts, each probed, a failure a warning', () async {
      final checks = await hostChecks('.', probe: (h) async =>
          (host: h, ok: h != 'esimple.transasim.com', daysLeft: 30, detail: h == 'esimple.transasim.com' ? 'expired' : 'valid'));
      expect(checks.every((c) => c.group == 'Hosts'), isTrue);
      expect(checks.map((c) => c.label), containsAll(['acorn PRODUCTION acorn-api.transasim.com', 'acorn DEV acorn.transasim.com',
          'sabily PRODUCTION api.sabily.fr', 'sabily DEV api.sabily.transasim.com']));
      expect(checks.where((c) => c.status == 'warn').map((c) => c.label), everyElement(contains('esimple.transasim.com')));
    });
  });
}

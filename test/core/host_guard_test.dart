import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../tool/studio/src/generate.dart' show readStudio;
import '../../tool/studio/src/hosts.dart';

/// Slice H: a store or TestFlight build never talks to a DEV server. In
/// October 2026 eSimple's store app was built against its DEV host, and two
/// months of its customers and payments went into the DEV database.

/// The hosts the brands may use, as given with the Slice H request
/// (2026-10-20, with its correction on api.esimple.transasim.com).
const _production = {
  'esimple': 'api.esimple.at',
  'acorn': 'acorn-api.transasim.com',
  'sabily': 'api.sabily.fr',
};
const _dev = {
  'esimple': 'esimple.transasim.com',
  'acorn': 'acorn.transasim.com',
  'sabily': 'api.sabily.transasim.com',
};

/// eSimple's production alias: one nginx server block on 80.241.216.126 sends
/// it and api.esimple.at to its production backend. Never a DEV host.
const _esimpleAlias = 'api.esimple.transasim.com';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('(a) every brand\'s store build talks to its production host', () {
    for (final MapEntry(key: slug, value: host) in _production.entries) {
      test(slug, () {
        final studio = readStudio('.', slug);
        final bundle = _json('brands/$slug/flavor/$slug.json')['mobile'] as Map;
        // The pin is the production host, whatever stands in for it today.
        expect(hostOf(pinnedApiBaseUrl(studio)), host);
        final exception = productionException(studio);
        if (slug == 'esimple') {
          // Until the server merge, eSimple's store builds stay where its
          // app customers' accounts are: a recorded, temporary exception.
          expect(exception?.reason, 'DEV server serving as production until the merge');
          expect(hostOf('${bundle['apiBaseUrl']}'), hostOf(exception!.apiBaseUrl));
          expect(hostOf(exception.apiBaseUrl), _dev['esimple']);
          expect(pinnedHosts(studio), {host, _esimpleAlias});
        } else {
          expect(exception, isNull);
          expect(hostOf('${bundle['apiBaseUrl']}'), host);
        }
        expect(bundle.containsKey('devApiBaseUrl'), isFalse, reason: 'the store bundle names no DEV host');
        // And its entry point refuses any other host.
        expect(hostRefusal(slug, AppFlavor.prod, '${bundle['apiBaseUrl']}', productionHosts(studio)), isNull);
      });
    }

    test('no DEV host is ever a production one, an alias included', () {
      for (final slug in _production.keys) {
        final studio = readStudio('.', slug);
        for (final dev in _dev.entries) {
          if (dev.key == 'esimple' && slug == 'esimple') continue; // the recorded exception
          expect(productionHosts(studio), isNot(contains(dev.value)), reason: '$slug lists ${dev.value}');
        }
      }
      expect(_dev.values, isNot(contains(_esimpleAlias)));
      expect(devHosts('.').keys, isNot(contains(_esimpleAlias)));
    });

    test('every DEV build talks to its brand\'s DEV host, and refuses production', () {
      for (final MapEntry(key: slug, value: host) in _dev.entries) {
        final file = File('brands/$slug/flavor/${slug}Dev.json');
        if (!file.existsSync()) {
          expect(slug, 'esimple', reason: 'only eSimple has no DEV build: its DEV server is its production');
          continue;
        }
        final mobile = _json(file.path)['mobile'] as Map;
        expect(hostOf('${mobile['apiBaseUrl']}'), host);
        expect('${mobile['applicationId']}', endsWith('.dev'));
        expect(hostRefusal(slug, AppFlavor.dev, '${mobile['apiBaseUrl']}', productionHosts(readStudio('.', slug))), isNull);
      }
    });
  });

  test('(b) no code or native config names a server host, but each brand\'s own entry points', () {
    // Dart, Gradle, plist, xcconfig and entitlements files, tracked or new,
    // outside brands/ (its config) and test/ (fixtures, listed below). Docs
    // and Studio's web pages are not code that ships.
    final files = [
      for (final f in '${Process.runSync('git', ['ls-files', '--cached', '--others', '--exclude-standard']).stdout}'
          .split('\n')
          .map((l) => l.trim()))
        if (RegExp(r'\.(dart|gradle|kts|plist|xcconfig|entitlements)$').hasMatch(f) &&
            !f.startsWith('brands/') &&
            !f.startsWith('test/') &&
            File(f).existsSync())
          f,
    ];
    expect(files, contains('lib/main_common.dart'), reason: 'git listed no files: run from the repo root');
    final hosts = RegExp(r'[A-Za-z0-9.-]*transasim\.com|api\.esimple\.at|api\.sabily\.fr');
    final found = <String>[];
    for (final f in files) {
      // The one exception: a brand's generated entry points carry its own
      // production hosts, from studio.json (acorn-api.transasim.com for
      // Acorn; api.esimple.at, its alias api.esimple.transasim.com and, while
      // the exception stands, esimple.transasim.com for eSimple).
      final slug = RegExp(r'^lib/flavors/main_([a-z0-9]+?)(_dev)?\.dart$').firstMatch(f)?[1];
      final allowed = slug == null ? const <String>[] : productionHosts(readStudio('.', slug));
      for (final m in hosts.allMatches(File(f).readAsStringSync())) {
        if (!allowed.contains(m[0])) found.add('$f: ${m[0]}');
      }
    }
    expect(found, isEmpty);
  });

  group('(d) a build on the wrong host does not start', () {
    const acorn = ['acorn-api.transasim.com'];
    test('a store build on a DEV host, or on none', () {
      expect(hostRefusal('acorn', AppFlavor.prod, 'https://acorn.transasim.com/api', acorn),
          allOf(contains('acorn.transasim.com'), contains("not acorn's production host")));
      expect(hostRefusal('acorn', AppFlavor.prod, '', acorn), contains('no production host'));
      expect(hostRefusal('acorn', AppFlavor.prod, 'https://acorn-api.transasim.com/api', const []), isNotNull,
          reason: 'an entry point with no hosts compiled in starts on none');
    });
    test('a DEV build on a production host', () {
      expect(hostRefusal('acorn', AppFlavor.dev, 'https://acorn-api.transasim.com/api', acorn),
          contains("acorn's production host"));
      expect(hostRefusal('acorn', AppFlavor.dev, 'https://acorn.transasim.com/api', acorn), isNull);
    });
    test('the host is compared whole, never as a part of another', () {
      expect(hostRefusal('acorn', AppFlavor.prod, 'https://acorn-api.transasim.com.evil.example/api', acorn), isNotNull);
      expect(hostRefusal('acorn', AppFlavor.prod, 'https://ACORN-API.transasim.com/api', acorn), isNull);
    });
    test('Stripe: a store build takes pk_live_ only, a DEV build pk_test_ only', () {
      expect(stripeModeFor(AppFlavor.prod), 'live');
      expect(stripeModeFor(AppFlavor.dev), 'test');
      expect(stripeKeyMode('pk_live_${'a' * 30}'), 'live');
      expect(stripeKeyMode('pk_test_${'a' * 30}'), 'test');
      for (final k in ['pk_test_PLACEHOLDER_AWAITING_CLIENT', 'sk_live_${'a' * 30}', 'pk_live_short', '']) {
        expect(stripeKeyMode(k), isNull, reason: k);
      }
    });
  });
}

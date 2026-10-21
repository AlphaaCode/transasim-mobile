/// eSimple's store build talks to its production host, and the guard says so.
///
/// Until 21/10/2026 a standing exception made eSimple's store builds use its
/// DEV server (esimple.transasim.com) "until the merge". The exception is
/// ended: production is `https://api.esimple.at/api`, with
/// `api.esimple.transasim.com` allowed as the same server's alias. These read
/// the SHIPPED files, so a drift in any of them fails here and not on a phone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../tool/studio/src/generate.dart' show readStudio;
import '../../tool/studio/src/hosts.dart';

const _production = 'https://api.esimple.at/api';
const _alias = 'https://api.esimple.transasim.com/api';
const _dev = 'https://esimple.transasim.com/api';

void main() {
  final brand = jsonDecode(File('brands/esimple/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final studio = readStudio('.', 'esimple');
  final hosts = productionHosts(studio);
  final mobile = brand['mobile'] as Map;

  group('the store build points at production', () {
    test('brand.json carries the production URL, which is the pin', () {
      expect(mobile['apiBaseUrl'], _production);
      expect(expectedApiBaseUrl(studio), _production);
    });

    test('no exception stands, so nothing sends the store build to DEV', () {
      expect(productionException(studio), isNull);
    });

    test('the store bundle ships that URL and no DEV value', () {
      final bundle = flavorBundle(brand, AppFlavor.prod)['mobile'] as Map;
      expect(bundle['apiBaseUrl'], _production);
      expect(bundle.containsKey('devApiBaseUrl'), isFalse);
    });

    test('the URL ends in /api, because every request path is relative to it', () {
      expect(Uri.parse(mobile['apiBaseUrl'] as String).path, '/api');
    });
  });

  group('the host guard', () {
    test('compiles in api.esimple.at and its alias, and not the DEV host', () {
      expect(hosts, containsAll(<String>['api.esimple.at', 'api.esimple.transasim.com']));
      expect(hosts, isNot(contains('esimple.transasim.com')));
    });

    test('lets the store build start on api.esimple.at and on the alias', () {
      expect(hostRefusal('esimple', AppFlavor.prod, _production, hosts), isNull);
      expect(hostRefusal('esimple', AppFlavor.prod, _alias, hosts), isNull);
    });

    test('refuses the store build on the DEV host, which is what this was about', () {
      expect(hostRefusal('esimple', AppFlavor.prod, _dev, hosts), isNotNull);
    });
  });

  group('the dev build stays on the dev host, kept apart', () {
    test('devApiBaseUrl is the DEV server, and the dev bundle ships it', () {
      expect(mobile['devApiBaseUrl'], _dev);
      final bundle = flavorBundle(brand, AppFlavor.dev)['mobile'] as Map;
      expect(bundle['apiBaseUrl'], _dev);
    });

    test('the dev build may use the DEV host and may not use production', () {
      expect(hostRefusal('esimple', AppFlavor.dev, _dev, hosts), isNull);
      expect(hostRefusal('esimple', AppFlavor.dev, _production, hosts), isNotNull);
    });
  });
}

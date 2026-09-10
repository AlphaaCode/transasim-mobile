import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/modules/app_module.dart';
import 'package:transasim_mobile/core/result/result.dart';
import 'package:transasim_mobile/modules/wallet/wallet_module.dart';

import 'brand_config_test.dart' show validJson;

BrandConfig brandWith({required bool wallet}) {
  final json = validJson()..['features'] = {'wallet': wallet};
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

/// A second optional module, used to prove the registry is not hard-wired to
/// the one module the socle happens to ship today.
class _AlwaysOnModule extends AppModule {
  const _AlwaysOnModule();
  @override
  String get id => 'always';
  @override
  bool isEnabled(BrandConfig config) => true;
  @override
  List<RouteBase> routes(BrandConfig config) =>
      [GoRoute(path: '/always', builder: (_, _) => const SizedBox.shrink())];
  @override
  List<NavEntry> navEntries(BrandConfig config) => const [];
}

void main() {
  const modules = <AppModule>[WalletModule(), _AlwaysOnModule()];

  group('the flag is honest — ARCHITECTURE-MOBILE.md §8.4', () {
    // This is the test that stops `features.wallet` becoming the old app's
    // FEATURE_CREDIT_CARD, which hid one of four entry points and closed none
    // of the routes (ANALYSE-EXISTANT.md §4.10).

    final off = ModuleRegistry(all: modules, config: brandWith(wallet: false));
    final on = ModuleRegistry(all: modules, config: brandWith(wallet: true));

    test('1. the route is NOT REGISTERED when the flag is off', () {
      final paths = off.routes.whereType<GoRoute>().map((r) => r.path);
      expect(paths, isNot(contains('/wallet')));
      expect(paths, contains('/always'), reason: 'other modules are unaffected');
    });

    test('2. the tab is absent when the flag is off', () {
      expect(off.navEntries.map((e) => e.moduleId), isNot(contains('wallet')));
    });

    test('3. the use-case guard refuses even if something reaches it', () {
      // The deep link, the named navigation and the network call all still
      // exist in the binary. Closing the route is only half the mechanism.
      final result = off.guard<String>('wallet', () => 'provisioned');

      expect(result, isA<Err<String>>());
      final error = result.errorOrNull;
      expect(error, isA<FeatureUnavailable>());
      expect((error as FeatureUnavailable).moduleId, 'wallet');
    });

    test('with the flag on, all three open up', () {
      expect(on.routes.whereType<GoRoute>().map((r) => r.path), contains('/wallet'));
      expect(on.navEntries.map((e) => e.moduleId), contains('wallet'));
      expect(on.guard<String>('wallet', () => 'ok'), isA<Ok<String>>());
    });
  });

  group('the registry', () {
    test('a module that is off instantiates nothing', () {
      final off = ModuleRegistry(all: modules, config: brandWith(wallet: false));
      expect(off.active.map((m) => m.id), <String>['always']);
      expect(off.isActive('wallet'), isFalse);
    });

    test('nav entries carry a dictionary key, never a literal label', () {
      final on = ModuleRegistry(all: modules, config: brandWith(wallet: true));
      final entry = on.navEntries.firstWhere((e) => e.moduleId == 'wallet');
      // A label that is already human-readable here could never be translated.
      expect(entry.labelKey, 'nav.wallet');
      expect(entry.labelKey, isNot(contains(' ')));
    });
  });
}

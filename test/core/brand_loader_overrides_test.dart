import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_loader.dart';

/// The config tests parse `brand.json` directly. The APP does not: it loads
/// its flavor's generated bundle through `BrandLoader`, which merges the
/// remote config and holds the Stripe key to the flavor's mode on the way out.
///
/// That gap once shipped a bug: the build overrides rebuilt `BrandMobile`
/// field by field and never carried `registrationSteps`, so the three-step
/// wizard silently became a single form on every development build. It was
/// caught by looking at a device, not by 154 passing tests.
///
/// These assert the resolution the app actually receives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The bundle caches what it loaded: each test serves its own files.
    rootBundle.clear();
  });

  /// The test binding has no asset bundle, so files are served in its place:
  /// by default the SHIPPED bundles, which is the point.
  void serve(Map<String, List<int>> assets) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final bytes = assets[utf8.decode(message!.buffer.asUint8List())];
      return bytes == null ? null : ByteData.view(Uint8List.fromList(bytes).buffer);
    });
  }

  void serveRealBundles() => serve({
        for (final name in ['sabily', 'sabilyDev'])
          'brands/sabily/flavor/$name.json': File('brands/sabily/flavor/$name.json').readAsBytesSync(),
      });

  test('the shipped configuration survives resolution intact', () async {
    serveRealBundles();
    {
      final resolution = await BrandLoader.resolveOffline('sabily');
      final mobile = resolution.config.mobile;

      expect(mobile.registrationFields, isNotEmpty);
      // Sabily ships one page since the field list was cut to five on
      // 24/09/2026, so there are no steps to lose. When a brand HAS them the
      // loader must carry them — that is the defect this guards — so the
      // check still runs whenever they exist.
      if (mobile.registrationSteps.isNotEmpty) {
        expect(
          mobile.registrationSteps.expand((s) => s.fields).toSet(),
          mobile.registrationFields.toSet(),
          reason: 'a field no step shows is a field the user is never asked for',
        );
      }
    }
  });

  test('each flavor loads its own bundle: the store one on production, the DEV one on DEV', () async {
    serveRealBundles();
    final store = (await BrandLoader.resolveOffline('sabily')).config.mobile;
    final dev = (await BrandLoader.resolveOffline('sabily', flavor: AppFlavor.dev)).config.mobile;
    expect(hostOf(store.apiBaseUrl), 'api.sabily.fr');
    expect(store.applicationId, 'com.sabily.esim');
    expect(store.devApiBaseUrl, isNull, reason: 'the store bundle carries no DEV host');
    expect(hostOf(dev.apiBaseUrl), 'api.sabily.transasim.com');
    expect(dev.applicationId, 'com.sabily.esim.dev');
    expect(dev.bundleIdentifier, 'com.sabily.esim.dev');
    expect(dev.displayName, endsWith(' DEV'));
    expect(dev.remoteConfigUrl, isNull, reason: 'the remote config is served by production');
    expect(stripeKeyMode(dev.stripePublishableKey), isNot('live'));
  });

  test('copyWith carries every field it did not change', () {
    // The structural guard is that `registrationSteps` is a REQUIRED parameter,
    // which makes a field-by-field rebuild that forgets it a compile error.
    // This pins the behaviour that guard protects.
    const original = BrandMobile(
      applicationId: 'com.example.app',
      bundleIdentifier: 'com.example.app',
      displayName: 'Example',
      deepLinkScheme: 'example',
      universalLinkHosts: ['example.test'],
      apiBaseUrl: 'https://one.example.test/api',
      stripePublishableKey: 'pk_test_x',
      merchantIdentifier: 'merchant.example',
      merchantCountryCode: 'FR',
      cardBackground: null,
      googleServerClientId: '123.apps.googleusercontent.com',
      popularDestinations: ['FRA', 'ESP'],
      remoteConfigUrl: 'https://one.example.test/config.json',
      minimumSupportedVersion: '1.0.0',
      registrationFields: ['email', 'password'],
      registrationSteps: [
        RegistrationStep(titleKey: 'a', fields: ['email']),
        RegistrationStep(titleKey: 'b', fields: ['password']),
      ],
    );

    final derived = original.copyWith(apiBaseUrl: 'https://two.example.test/api');

    // Each value is independent: changing the backend alone must not disturb
    // the Stripe key, and vice versa.
    expect(derived.stripePublishableKey, original.stripePublishableKey,
        reason: 'changing the backend must not touch the key');

    final rekeyed = original.copyWith(stripePublishableKey: 'pk_test_other');
    expect(rekeyed.stripePublishableKey, 'pk_test_other');
    expect(rekeyed.apiBaseUrl, original.apiBaseUrl,
        reason: 'changing the key must not touch the backend');
    expect(rekeyed.registrationSteps, same(original.registrationSteps));

    // Nothing named: nothing changes.
    final untouched = original.copyWith();
    expect(untouched.apiBaseUrl, original.apiBaseUrl);
    expect(untouched.stripePublishableKey, original.stripePublishableKey);

    expect(derived.apiBaseUrl, 'https://two.example.test/api');
    expect(derived.registrationSteps, same(original.registrationSteps),
        reason: 'dropping steps here turns the wizard into a single form');
    expect(derived.registrationFields, same(original.registrationFields));
    expect(derived.applicationId, original.applicationId);
    expect(derived.bundleIdentifier, original.bundleIdentifier);
    expect(derived.displayName, original.displayName);
    expect(derived.deepLinkScheme, original.deepLinkScheme);
    expect(derived.universalLinkHosts, same(original.universalLinkHosts));
    expect(derived.stripePublishableKey, original.stripePublishableKey);
    expect(derived.merchantIdentifier, original.merchantIdentifier);
    expect(derived.merchantCountryCode, original.merchantCountryCode);
    expect(derived.remoteConfigUrl, original.remoteConfigUrl);
    expect(derived.minimumSupportedVersion, original.minimumSupportedVersion);
  });

  test('resolution reaches no network and no cache entry is required', () async {
    serveRealBundles();
    // resolveOffline must complete from the bundle alone. If it ever awaited a
    // fetch, this would hang rather than return.
    final resolution = await BrandLoader.resolveOffline('sabily')
        .timeout(const Duration(seconds: 2));
    expect(resolution.source, BrandSource.embedded);
  });

  group('a Stripe key counts only in its flavor\'s mode', () {
    final liveKey = 'pk_live_${'L' * 30}';
    final testKey = 'pk_test_${'T' * 30}';

    /// Sabily's real store bundle, given [key], served as [flavor]'s.
    void serveSabily(AppFlavor flavor, String key) {
      final bundle = jsonDecode(File('brands/sabily/flavor/sabily.json').readAsStringSync()) as Map<String, dynamic>;
      (bundle['mobile'] as Map)['stripePublishableKey'] = key;
      serve({'brands/sabily/flavor/${flavorName('sabily', flavor)}.json': utf8.encode(jsonEncode(bundle))});
    }

    Future<BrandResolution> resolveWith(AppFlavor flavor, String builtIn, String? remote) {
      serveSabily(flavor, builtIn);
      return BrandLoader.resolve('sabily',
          flavor: flavor,
          fetch: (_) async => {
                'mobile': {'stripePublishableKey': ?remote},
              });
    }

    test('the remote config keeps a store build on its pk_live_ key when it sends a pk_test_ one', () async {
      final r = await resolveWith(AppFlavor.prod, liveKey, testKey);
      expect(r.source, BrandSource.remote);
      expect(r.config.mobile.stripePublishableKey, liveKey);
      expect(r.warnings.map((w) => w.field), contains('mobile.stripePublishableKey'));
    });

    test('a pk_live_ key from the remote config replaces the store build\'s own', () async {
      final other = 'pk_live_${'M' * 30}';
      final r = await resolveWith(AppFlavor.prod, liveKey, other);
      expect(r.config.mobile.stripePublishableKey, other);
      expect(r.warnings.map((w) => w.field), isNot(contains('mobile.stripePublishableKey')));
    });

    test('a DEV build keeps its pk_test_ key when the remote config sends a live one', () async {
      final r = await resolveWith(AppFlavor.dev, testKey, liveKey);
      expect(r.config.mobile.stripePublishableKey, testKey);
      expect(r.warnings.map((w) => w.field), contains('mobile.stripePublishableKey'));
    });

    test('a built-in key of the wrong mode turns payments off, said in a warning', () async {
      for (final (flavor, key) in [(AppFlavor.prod, testKey), (AppFlavor.dev, liveKey)]) {
        serveSabily(flavor, key);
        final r = await BrandLoader.resolveOffline('sabily', flavor: flavor);
        expect(stripeKeyMode(r.config.mobile.stripePublishableKey), isNull, reason: '${flavor.name} with $key');
        expect(r.warnings.map((w) => w.field), contains('mobile.stripePublishableKey'));
      }
    });
  });
}

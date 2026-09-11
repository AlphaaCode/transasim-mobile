import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_loader.dart';

/// The config tests parse `brand.json` directly. The APP does not — it goes
/// through `BrandLoader`, which applies build overrides on the way out.
///
/// That gap shipped a bug: `_applyBuildOverrides` rebuilt `BrandMobile` field
/// by field and never carried `registrationSteps`, so the three-step wizard
/// silently became a single form on every build with `--dart-define=
/// API_BASE_URL` — which is every development build. It was caught by looking
/// at a device, not by 154 passing tests.
///
/// These assert the resolution the app actually receives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The test binding has no asset bundle, so the real file is served in its
  /// place — which is the point: this must exercise the SHIPPED config.
  void serveRealBundle() {
    final data = File('brands/sabily/brand.json').readAsBytesSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'brands/sabily/brand.json') {
        return ByteData.view(Uint8List.fromList(data).buffer);
      }
      return null;
    });
  }

  test('the shipped configuration survives resolution intact', () async {
    serveRealBundle();
    {
      final resolution = await BrandLoader.resolveOffline('sabily');
      final mobile = resolution.config.mobile;

      expect(mobile.registrationFields, isNotEmpty);
      expect(mobile.registrationSteps, isNotEmpty,
          reason: 'the wizard disappears if steps do not survive the loader');
      expect(
        mobile.registrationSteps.expand((s) => s.fields).toSet(),
        mobile.registrationFields.toSet(),
        reason: 'a field no step shows is a field the user is never asked for',
      );
    }
  });

  test('copyWith carries every field it did not change', () {
    // THE test for the actual defect. The loader test above does NOT catch it:
    // `_applyBuildOverrides` is guarded by `String.fromEnvironment`, which is
    // compile-time, so under a plain `flutter test` the override branch never
    // runs at all. This exercises the derivation directly.
    //
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
      remoteConfigUrl: 'https://one.example.test/config.json',
      minimumSupportedVersion: '1.0.0',
      registrationFields: ['email', 'password'],
      registrationSteps: [
        RegistrationStep(titleKey: 'a', fields: ['email']),
        RegistrationStep(titleKey: 'b', fields: ['password']),
      ],
    );

    final derived = original.copyWith(apiBaseUrl: 'https://two.example.test/api');

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
    serveRealBundle();
    // resolveOffline must complete from the bundle alone. If it ever awaited a
    // fetch, this would hang rather than return.
    final resolution = await BrandLoader.resolveOffline('sabily')
        .timeout(const Duration(seconds: 2));
    expect(resolution.source, BrandSource.embedded);
  });
}

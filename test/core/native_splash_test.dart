import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The launch window is painted by the OS before any Dart runs, so it cannot
/// read `brand.json`. Its colour is therefore duplicated into the flavor's
/// Android resources — the one place in the repo a brand colour is repeated.
///
/// This is the test that stops the duplicate drifting. Without it, changing a
/// brand's surface leaves the splash on the old colour and the app flashes
/// from one cream to another on every cold start.
void main() {
  test('the flavor splash colour matches the brand surface', () {
    final brand = jsonDecode(File('brands/sabily/brand.json').readAsStringSync())
        as Map<String, dynamic>;
    final surface = ((brand['colors'] as Map)['surface'] as String).toLowerCase();

    final colors = File('android/app/src/sabily/res/values/colors.xml').readAsStringSync();
    final match = RegExp(r'name="brand_splash_background">\s*(#[0-9a-fA-F]{6,8})\s*<')
        .firstMatch(colors);

    expect(match, isNotNull, reason: 'no brand_splash_background in the flavor resources');
    expect(match!.group(1)!.toLowerCase(), surface,
        reason: 'the launch window would flash a different cream than the app');
  });

  test('the Android 12 splash names a brand icon, not the launcher default', () {
    // Android 12 replaced the launch window with the SplashScreen API, which
    // shows the LAUNCHER ICON unless told otherwise — which is why an
    // unbranded Flutter logo was appearing for ~2s on every cold start.
    final styles =
        File('android/app/src/sabily/res/values-v31/styles.xml').readAsStringSync();
    expect(styles, contains('windowSplashScreenAnimatedIcon'));
    expect(styles, contains('windowSplashScreenBackground'));

    expect(File('android/app/src/sabily/res/drawable/brand_splash_icon.xml').existsSync(), isTrue);
    expect(File('android/app/src/sabily/res/mipmap-xxxhdpi/ic_launcher.png').existsSync(), isTrue,
        reason: 'without a flavor launcher icon the system splash draws the Flutter logo');
  });

  test('the socle ships no launcher art for a flavor to inherit', () {
    // main/ used to carry Flutter's template logo at five densities. A flavor
    // that overrode only one bucket still shipped the Flutter logo on every
    // other device — which is what was happening. With none in the socle, a
    // brand that forgets its icon fails the build instead of shipping wrong.
    final main = Directory('android/app/src/main/res');
    final strays = main
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.split(RegExp(r'[\/]')).last.startsWith('mipmap'))
        .toList();
    expect(strays, isEmpty, reason: 'socle mipmaps would be inherited by every flavor');

    // And the flavor covers every density, not just one.
    expect(
      File('android/app/src/sabily/res/mipmap-anydpi-v26/ic_launcher.xml').existsSync(),
      isTrue,
      reason: 'without an adaptive icon only the xxxhdpi bucket is branded',
    );
  });

  test('startup never reaches the network', () {
    // `resolveOffline` is the only resolution bootstrap is allowed to await.
    // A `fetch:` argument on the startup path would put an HTTP round trip,
    // with a timeout, in front of the first frame.
    final main = File('lib/main_common.dart').readAsStringSync();
    expect(main, contains('BrandLoader.resolveOffline('));
    expect(main.split('runApp(').first, isNot(contains('fetch:')),
        reason: 'a fetcher before runApp blocks first paint on a server');
  });
}

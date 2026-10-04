import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../tool/gen_brand_flavors.dart' show withBrandFlavors;

/// A client is a folder plus generated wiring, never code. For every folder
/// under brands/, this checks the whole contract: a clean config, every file it
/// names present, a one-line entry point, an Android flavor read from that
/// config rather than typed into Gradle, flavor-only assets, and a launch
/// window in the brand's colour.
///
/// A second client that passes this is a white-label client; one that needs
/// anything else is a fork in disguise.

List<String> get _slugs => Directory('brands')
    .listSync()
    .whereType<Directory>()
    .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
    .toList()
  ..sort();

/// `KEY = value` pairs of `ios/Flutter/<slug>.xcconfig`, comments and includes skipped.
Map<String, String> _xcconfig(String slug) => {
      for (final line in File('ios/Flutter/$slug.xcconfig').readAsLinesSync())
        if (RegExp(r'^\s*([A-Z_]+)\s*=(.*)$').firstMatch(line) case final m?)
          m.group(1)!: m.group(2)!.trim(),
    };

BrandConfig _load(String slug) {
  final json = jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final r = BrandConfig.parse(json, expectedSlug: slug);
  expect(r.errors, isEmpty, reason: r.describe(slug));
  return r.config as BrandConfig;
}

void main() {
  test('the shipped clients are present', () {
    expect(_slugs, containsAll(['acorn', 'esimple', 'sabily']));
  });

  for (final slug in _slugs) {
    group('brands/$slug', () {
      test('parses with no errors, and every file it names is in its own folder', () {
        final c = _load(slug);
        final named = [
          c.logo.mark,
          c.logo.full,
          ?c.logo.fullInverse,
          ?c.logo.intro,
          ...c.visuals.packImages.values,
        ];
        for (final file in named) {
          expect(File('brands/$slug/assets/$file').existsSync(), isTrue, reason: file);
        }
      });

      test('has a one-line entry point', () {
        final entry = File('lib/flavors/main_$slug.dart').readAsStringSync();
        expect(entry, contains("void main() => bootstrap('$slug');"));
      });

      test('gets its Android flavor from brand.json, not from a line of Gradle', () {
        // build.gradle.kts creates one productFlavor per brands/ folder and
        // reads its applicationId and label from brand.json. A slug or an id
        // written into it is a second source that can drift from the first,
        // and a client hand-wired into the socle.
        final c = _load(slug);
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();
        expect(gradle, isNot(contains('"$slug"')));
        expect(gradle, isNot(contains(c.mobile.applicationId)));
      });

      test('ships its assets into its own flavor only', () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        for (final path in ['brands/$slug/brand.json', 'brands/$slug/assets/']) {
          expect(pubspec, contains('- path: $path\n      flavors: [$slug]'),
              reason: '$path would ship inside every other client\'s app');
        }
      });

      test('paints its launch window in the colour the app paints next', () {
        // The intro animation's own edge colour, so the hand over from the OS
        // shows no flash; the brand's surface when there is no animation.
        final c = _load(slug);
        final colors = File('android/app/src/$slug/res/values/colors.xml').readAsStringSync();
        final value = RegExp(r'name="brand_splash_background">\s*#([0-9a-fA-F]{6})\s*<')
            .firstMatch(colors)
            ?.group(1);
        expect(value, isNotNull);
        expect(int.parse(value!, radix: 16) | 0xFF000000,
            (c.logo.introBackground ?? c.colors.surface).toARGB32());
        for (final f in [
          'res/values-v31/styles.xml',
          'res/drawable/brand_splash_icon.xml',
          'res/drawable/brand_mark.png',
          'res/mipmap-anydpi-v26/ic_launcher.xml',
          'res/mipmap-xxxhdpi/ic_launcher.png',
        ]) {
          expect(File('android/app/src/$slug/$f').existsSync(), isTrue, reason: f);
        }
      });

      test('has an iOS flavor carrying its frozen bundle id and name', () {
        final c = _load(slug);
        final x = _xcconfig(slug);
        expect(x['PRODUCT_BUNDLE_IDENTIFIER'], c.mobile.bundleIdentifier);
        expect(x['APP_DISPLAY_NAME'], c.mobile.displayName);
        // Only its own catalog: the target excludes every Brand-*.xcassets.
        expect(x['INCLUDED_SOURCE_FILE_NAMES'], 'Brand-$slug.xcassets');

        final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
        for (final type in ['Debug', 'Release', 'Profile']) {
          expect(pbxproj, contains('name = "$type-$slug";'), reason: 'no $type-$slug configuration');
        }
        // `flutter build ipa --flavor <slug>` archives with the scheme's
        // Archive configuration, so that is the one that must be Release.
        final scheme = File('ios/Runner.xcodeproj/xcshareddata/xcschemes/$slug.xcscheme');
        expect(scheme.existsSync(), isTrue, reason: 'no shared "$slug" scheme');
        expect(
          RegExp(r'<ArchiveAction\s+buildConfiguration\s*=\s*"([^"]+)"')
              .firstMatch(scheme.readAsStringSync())
              ?.group(1),
          'Release-$slug',
        );
      });

      test('paints its iOS launch screen in the colour the app paints next, under its own icon', () {
        final c = _load(slug);
        final catalog = 'ios/Runner/Brands/Brand-$slug.xcassets';
        final rgb = jsonDecode(File('$catalog/LaunchBackground.colorset/Contents.json')
            .readAsStringSync())['colors'][0]['color']['components'] as Map;
        int channel(String k) => int.parse(rgb[k] as String);
        expect(0xFF000000 | channel('red') << 16 | channel('green') << 8 | channel('blue'),
            (c.logo.introBackground ?? c.colors.surface).toARGB32());
        expect(File('$catalog/AppIcon.appiconset/AppIcon-1024.png').existsSync(), isTrue);
      });

      test('offers Google sign-in on iOS only with an iOS client to back it', () {
        // On iOS the plugin ignores the serverClientId Dart passes unless a
        // client ID comes with it, and reads both from Info.plist instead.
        // Without the iOS client the button fails on every tap.
        final c = _load(slug);
        final x = _xcconfig(slug);
        expect(x['GOOGLE_SERVER_CLIENT_ID'] ?? '', c.mobile.googleServerClientId ?? '');
        if (c.mobile.googleServerClientId == null) return;
        const suffix = '.apps.googleusercontent.com';
        final client = x['GOOGLE_IOS_CLIENT_ID'] ?? '';
        expect(client, endsWith(suffix), reason: 'no iOS OAuth client for $slug');
        expect(client, isNot(c.mobile.googleServerClientId), reason: 'that is the web client');
        expect(x['GOOGLE_REVERSED_CLIENT_ID'],
            'com.googleusercontent.apps.${client.substring(0, client.length - suffix.length)}');
      });
    });
  }

  test('pubspec.yaml ships exactly these brands, as the generator writes them', () {
    // Also catches the entries of a brand folder that has since been deleted.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(withBrandFlavors(pubspec, _slugs), pubspec,
        reason: 'run: dart run tool/gen_brand_flavors.dart');
  });

  test('no two clients share a store identity, a deep-link scheme or a backend', () {
    final all = _slugs.map(_load).toList();
    for (final pick in <String Function(BrandConfig)>[
      (c) => c.mobile.applicationId,
      (c) => c.mobile.bundleIdentifier,
      (c) => c.mobile.deepLinkScheme,
      (c) => c.mobile.apiBaseUrl,
      (c) => c.support.email,
    ]) {
      final values = all.map(pick).toList();
      expect(values.toSet().length, values.length, reason: values.join(', '));
    }
  });

  test('no client configuration is a copy-paste of another', () {
    // The screens cannot leak what the configuration does not hold, so the
    // config itself is checked: two clients may share only socle-level
    // values (locale codes, field names, placeholders), never a brand value.
    Set<String> leaves(Object? node) => switch (node) {
          String s => {s},
          Map m => {for (final v in m.values) ...leaves(v)},
          List l => {for (final v in l) ...leaves(v)},
          _ => <String>{},
        };
    const socle = {
      'fr', 'en', 'ar', 'es', 'sl', 'de', 'sq', 'EUR', '1.0.0', //
      'logo-mark.png', 'logo-full.png', 'logo-intro.mp4', '#000000',
      'pk_test_PLACEHOLDER_AWAITING_CLIENT',
      ...kKnownRegistrationFields,
      'account.step.identity', 'account.step.security', 'account.step.details',
    };
    final slugs = _slugs;
    for (var i = 0; i < slugs.length; i++) {
      for (var j = i + 1; j < slugs.length; j++) {
        Set<String> of(String slug) =>
            leaves(jsonDecode(File('brands/$slug/brand.json').readAsStringSync()));
        final shared = of(slugs[i]).intersection(of(slugs[j])).difference(socle);
        expect(shared, isEmpty, reason: '${slugs[i]} and ${slugs[j]} both say $shared');
      }
    }
  });

  test('each client plays its own animation, from its own folder', () {
    // The file name is the same convention for all of them, so what has to
    // differ is the bytes: a copy-paste would ship one brand's logo to another.
    final digests = <String, int>{};
    for (final slug in _slugs) {
      final intro = _load(slug).logo.intro;
      expect(intro, isNotNull, reason: '$slug has no intro animation');
      final bytes = File('brands/$slug/assets/$intro').readAsBytesSync();
      digests[slug] = Object.hashAll(bytes);
    }
    expect(digests.values.toSet().length, _slugs.length, reason: 'two clients ship the same video');
  });

  test('Acorn is what its config sheet and site say', () {
    final c = _load('acorn');
    expect(c.name, 'Odyssey Global SIM');
    expect(c.legal.companyName, 'Acorn Enterprises');
    expect(c.legal.legalForm, 'Sole Proprietorship');
    expect(c.legal.country, 'GB');
    // English only, as the client asked; not the socle's seven.
    expect(c.locales, ['en']);
    // The dev backend Alpha named, on the TRANSASIM host.
    expect(c.mobile.apiBaseUrl, 'https://acorn.transasim.com/api');
    // acorn.transasim.com's own tokens: blue #234CDE, surface #EEF6FD,
    // amber CTA #FFB21E with #0B2E6B text.
    expect(c.colors.primary.toARGB32(), 0xFF234CDE);
    expect(c.colors.surface.toARGB32(), 0xFFEEF6FD);
    expect(c.colors.cta.toARGB32(), 0xFFFFB21E);
    expect(c.mobile.stripePublishableKey, startsWith('pk_test_PLACEHOLDER'));
  });

  test("Acorn's missing identifiers are listed as gaps, not left silently blank", () {
    final json = jsonDecode(File('brands/acorn/brand.json').readAsStringSync()) as Map<String, dynamic>;
    final warned = BrandConfig.parse(json, expectedSlug: 'acorn').warnings.map((w) => w.field);
    expect(warned, containsAll(['legal.vatRate', 'legal.vatNumber', 'legal.rcs']));
  });

  test('eSimple is what its own sources say', () {
    final c = _load('esimple');
    // Published on both stores under this id (ARCHITECTURE-MOBILE.md §3.4).
    expect(c.mobile.applicationId, 'com.esimple.esim');
    expect(c.mobile.bundleIdentifier, 'com.esimple.esim');
    // The six esimple.at serves (hreflang), not Sabily's seven: no Spanish.
    expect(c.locales, unorderedEquals(['de', 'en', 'fr', 'ar', 'sl', 'sq']));
    expect(c.defaultLocale, 'de');
    expect(c.legal.country, 'AT');
    // The client has now supplied one, which is what this guard was waiting
    // for — so it becomes the same check Sabily gets: a PUBLISHABLE key and
    // never a secret one. `pk_` is safe in a client binary by design; an
    // `sk_` there would be the incident, and that is what this pins.
    expect(c.mobile.stripePublishableKey, startsWith('pk_'),
        reason: 'a publishable key, live or test — never a secret key');
    expect(c.mobile.stripePublishableKey, isNot(startsWith('sk_')));
  });
}

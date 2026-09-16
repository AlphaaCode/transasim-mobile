import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';

/// A client is a folder plus four lines of wiring, never code. For every
/// folder under brands/, this checks the whole contract: a clean config, every
/// file it names present, a one-line entry point, an Android flavor with the
/// frozen id, flavor-only assets, and a launch window in the brand's colour.
///
/// A second client that passes this is a white-label client; one that needs
/// anything else is a fork in disguise.

List<String> get _slugs => Directory('brands')
    .listSync()
    .whereType<Directory>()
    .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
    .toList()
  ..sort();

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

      test('has an Android flavor carrying its frozen applicationId and name', () {
        final c = _load(slug);
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();
        final block = RegExp('create\\("$slug"\\)\\s*\\{(.*?)\\n        \\}', dotAll: true)
            .firstMatch(gradle)
            ?.group(1);
        expect(block, isNotNull, reason: 'no productFlavor "$slug"');
        expect(block, contains('applicationId = "${c.mobile.applicationId}"'));
        expect(block, contains('resValue("string", "app_name", "${c.mobile.displayName}")'));
      });

      test('ships its assets into its own flavor only', () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        for (final path in ['brands/$slug/brand.json', 'brands/$slug/assets/']) {
          expect(pubspec, contains('- path: $path\n      flavors: [$slug]'),
              reason: '$path would ship inside every other client\'s app');
        }
      });

      test('paints its launch window in its own surface colour', () {
        final c = _load(slug);
        final colors = File('android/app/src/$slug/res/values/colors.xml').readAsStringSync();
        final value = RegExp(r'name="brand_splash_background">\s*#([0-9a-fA-F]{6})\s*<')
            .firstMatch(colors)
            ?.group(1);
        expect(value, isNotNull);
        expect(int.parse(value!, radix: 16) | 0xFF000000, c.colors.surface.toARGB32());
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
    });
  }

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
      'logo-mark.png', 'logo-full.png', 'pk_test_PLACEHOLDER_AWAITING_CLIENT',
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
    expect(c.mobile.stripePublishableKey, startsWith('pk_test_PLACEHOLDER'),
        reason: 'no live key until the client supplies one for the app');
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../tool/gen_brand_flavors.dart' show withBrandFlavors;
import '../../tool/studio/src/distinct.dart';

/// The clients that are published or built on both platforms. A brand added
/// since (by Studio, on Windows) may still be waiting for its Mac step.
const _shipped = ['acorn', 'esimple', 'sabily'];

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
    expect(_slugs, containsAll(_shipped));
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

      test("no qualified socle resource hides this flavor's own", () {
        // Android merges main/ and the flavor into one set, then picks the
        // most specific qualifier for the device, whichever set it came from.
        // A socle `drawable-v21/launch_background.xml` therefore beat every
        // flavor's `drawable/` one on Android 5–11, and a socle `values-night/`
        // beat every flavor's `values-v31/` splash in dark mode. A file a
        // flavor overrides must not also exist in a socle folder the flavor
        // lacks.
        String rel(FileSystemEntity f, String base) =>
            f.path.replaceAll(r'\', '/').substring(base.length + 1);
        final mine = [
          for (final f in Directory('android/app/src/$slug/res').listSync(recursive: true).whereType<File>())
            rel(f, 'android/app/src/$slug/res'),
        ];
        String type(String dir) => dir.split('-').first;
        final shadows = [
          for (final f in Directory('android/app/src/main/res').listSync(recursive: true).whereType<File>())
            if (rel(f, 'android/app/src/main/res').split('/') case [final dir, final name]
                when dir.contains('-') &&
                    !mine.contains('$dir/$name') &&
                    mine.any((m) => m.endsWith('/$name') && type(m.split('/').first) == type(dir)))
              'main/res/$dir/$name',
        ];
        expect(shadows, isEmpty);
      });

      test('has an iOS flavor carrying its frozen bundle id and name', () {
        final c = _load(slug);
        final x = _xcconfig(slug);
        expect(x['PRODUCT_BUNDLE_IDENTIFIER'], c.mobile.bundleIdentifier);
        expect(x['APP_DISPLAY_NAME'], c.mobile.displayName);
        // Only its own catalog: the target excludes every Brand-*.xcassets.
        expect(x['INCLUDED_SOURCE_FILE_NAMES'], 'Brand-$slug.xcassets');
      });

      // Adding a brand to the Xcode project takes `ruby tool/ios_flavors.rb`,
      // which runs only on the Mac. A brand made on Windows has its xcconfig
      // and asset catalog (checked here regardless) and none of this yet:
      // pending, not broken. A shipped brand, or one wired halfway, must be
      // wired completely.
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final scheme = File('ios/Runner.xcodeproj/xcshareddata/xcschemes/$slug.xcscheme');
      const types = ['Debug', 'Release', 'Profile'];
      final unwired = !_shipped.contains(slug) &&
          !scheme.existsSync() &&
          !types.any((t) => pbxproj.contains('name = "$t-$slug";'));
      test('is wired into the Xcode project, with configurations and a shared scheme', () {
        for (final type in types) {
          expect(pbxproj, contains('name = "$type-$slug";'), reason: 'no $type-$slug configuration');
        }
        // `flutter build ipa --flavor <slug>` archives with the scheme's
        // Archive configuration, so that is the one that must be Release.
        expect(scheme.existsSync(), isTrue, reason: 'no shared "$slug" scheme');
        expect(
          RegExp(r'<ArchiveAction\s+buildConfiguration\s*=\s*"([^"]+)"')
              .firstMatch(scheme.readAsStringSync())
              ?.group(1),
          'Release-$slug',
        );
      }, skip: unwired ? 'not in the Xcode project yet: run ruby tool/ios_flavors.rb on the Mac' : false);

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

  // The rules below live in tool/studio/src/distinct.dart, which Studio also
  // checks before Apply: one definition, enforced before and after.
  Map<String, dynamic> raw(String slug) =>
      jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

  test('no two clients share a store identity, a deep-link scheme or a backend', () {
    for (final path in kUniqueBrandPaths) {
      final values = [for (final slug in _slugs) valueAt(raw(slug), path)];
      expect(values.toSet().length, values.length, reason: '$path: ${values.join(', ')}');
    }
  });

  test('no client configuration is a copy-paste of another', () {
    // The screens cannot leak what the configuration does not hold, so the
    // config itself is checked: two clients may share only socle-level
    // values (locale codes, field names, placeholders, Studio's asset file
    // names), never a brand value.
    final slugs = _slugs;
    for (var i = 0; i < slugs.length; i++) {
      for (var j = i + 1; j < slugs.length; j++) {
        final shared = brandValues(raw(slugs[i])).keys.toSet()
            .intersection(brandValues(raw(slugs[j])).keys.toSet())
            .where((v) => !isSocleValue(v));
        expect(shared, isEmpty, reason: '${slugs[i]} and ${slugs[j]} both say $shared');
      }
    }
  });

  test('each client opens the way its config says, and no other way', () {
    // The style is the authority. Nothing here may branch on a slug; what is
    // asserted is that each brand's declared style and its files agree.
    for (final slug in _slugs) {
      final c = _load(slug);
      switch (c.intro.style) {
        case IntroStyle.video:
          expect(c.logo.intro, isNotNull, reason: '$slug plays a video but names no file');
          expect(File('brands/$slug/assets/${c.logo.intro}').existsSync(), isTrue,
              reason: '$slug names a video that is not in its folder');
        case IntroStyle.logoHold:
          // The hold shows logo.mark, so THAT is what must exist. A leftover
          // video would ship for nothing, and the config warns about it.
          expect(File('brands/$slug/assets/${c.logo.mark}').existsSync(), isTrue,
              reason: '$slug holds a mark that is not in its folder');
          expect(c.logo.intro, isNull,
              reason: '$slug holds its logo but still carries a video entry');
          expect(c.intro.logoHoldMin, lessThanOrEqualTo(c.intro.logoHoldMax), reason: slug);
      }
    }
  });

  test('each client that plays an animation plays its own, from its own folder', () {
    // The file name is the same convention for all of them, so what has to
    // differ is the bytes: a copy-paste would ship one brand's logo to another.
    final digests = <String, int>{};
    for (final slug in _slugs) {
      final intro = _load(slug).logo.intro;
      if (intro == null) continue;
      digests[slug] = Object.hashAll(File('brands/$slug/assets/$intro').readAsBytesSync());
    }
    expect(digests.values.toSet().length, digests.length, reason: 'two clients ship the same video');
  });

  test('the shipped brands split across both styles', () {
    // Not a preference — it is what keeps BOTH paths exercised by the real
    // configs. If every brand ends up on one style, the other rots.
    final styles = {for (final slug in _slugs) slug: _load(slug).intro.style};
    expect(styles['sabily'], IntroStyle.video);
    expect(styles['acorn'], IntroStyle.video);
    expect(styles['esimple'], IntroStyle.logoHold);
  });

  test('a brand with no intro block is refused, loudly', () {
    final raw = jsonDecode(File('brands/sabily/brand.json').readAsStringSync())
        as Map<String, dynamic>;
    raw.remove('intro');
    final r = BrandConfig.parse(raw, expectedSlug: 'sabily');
    expect(r.config, isNull, reason: 'it must not fall back to a default opening');
    expect(r.errors.join(' '), contains('intro'));
  });

  test('an unknown style names itself in the error', () {
    final raw = jsonDecode(File('brands/sabily/brand.json').readAsStringSync())
        as Map<String, dynamic>;
    raw['intro'] = {'style': 'fireworks'};
    final r = BrandConfig.parse(raw, expectedSlug: 'sabily');
    expect(r.config, isNull);
    expect(r.errors.join(' '), allOf(contains('fireworks'), contains('intro.style')));
  });

  test('a hold whose floor is above its ceiling is refused', () {
    final raw = jsonDecode(File('brands/esimple/brand.json').readAsStringSync())
        as Map<String, dynamic>;
    raw['intro'] = {'style': 'logoHold', 'logoHoldMinMs': 9000, 'logoHoldMaxMs': 4000};
    final r = BrandConfig.parse(raw, expectedSlug: 'esimple');
    expect(r.errors.join(' '), contains('logoHoldMinMs'));
  });

  test('Acorn is what its config sheet and site say', () {
    final c = _load('acorn');
    expect(c.name, 'Odyssey Global SIM');
    expect(c.legal.companyName, 'Acorn Enterprises');
    expect(c.legal.legalForm, 'Sole Proprietorship');
    expect(c.legal.country, 'GB');
    // English only, as the client asked; not the socle's seven.
    expect(c.locales, ['en']);
    // Its own production backend, on the TRANSASIM host (the DEV one was acorn.transasim.com).
    expect(c.mobile.apiBaseUrl, 'https://acorn-api.transasim.com/api');
    // acorn.transasim.com's own tokens: blue #234CDE, surface #EEF6FD,
    // amber CTA #FFB21E with #0B2E6B text.
    expect(c.colors.primary.toARGB32(), 0xFF234CDE);
    expect(c.colors.surface.toARGB32(), 0xFFEEF6FD);
    expect(c.colors.cta.toARGB32(), 0xFFFFB21E);
    // The client's own live publishable key (given by Alpha 2026-10-16); payments are on.
    expect(c.mobile.stripePublishableKey, matches(RegExp(r'^pk_live_[A-Za-z0-9]{24,}$')));
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

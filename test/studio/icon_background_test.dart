/// `logo.iconBackground`: a launcher icon on a different colour from the
/// launch window.
///
/// One resource, `brand_splash_background`, drove both the adaptive icon's
/// background layer and the native launch window. eSimple wants a navy icon
/// and a black entry, and changing the shared colour would have moved the
/// splash and the intro video's edges with it.
///
/// ⚠️ The field is OPTIONAL and must stay invisible when absent. A brand that
/// does not set it has to generate byte-identically to before, which is what
/// the first group here holds — `golden_master_test` would otherwise catch it
/// as drift across all three brands at once.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../tool/studio/src/generate.dart';

Map<String, dynamic> _brand(String slug) =>
    jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

/// The generated body of one path, for a brand given [logo] overrides.
String _render(String slug, Map<String, dynamic> logoPatch, String endsWith) {
  final brand = _brand(slug);
  brand['logo'] = {...brand['logo'] as Map<String, dynamic>, ...logoPatch};
  final change = generate('.', slug, brand).firstWhere((c) => c.path.endsWith(endsWith));
  return change.after;
}

void main() {
  group('absent: nothing is emitted and nothing is referenced', () {
    test('colors.xml holds only the splash colour', () {
      final xml = _render('sabily', {}, 'res/values/colors.xml');
      expect(xml, contains('brand_splash_background'));
      expect(xml, isNot(contains('brand_icon_background')),
          reason: 'a brand that did not ask for it must not grow a resource');
    });

    test('the adaptive icon still points at the splash colour', () {
      final xml = _render('sabily', {}, 'mipmap-anydpi-v26/ic_launcher.xml');
      expect(xml, contains('<background android:drawable="@color/brand_splash_background" />'));
      expect(xml, isNot(contains('brand_icon_background')));
    });

    test('an invalid value is ignored rather than written out', () {
      // Tolerant like the rest of templateValues: a half-typed colour in
      // Studio must not emit a resource Android cannot parse.
      for (final bad in <Object>['navy', '#2f3b4', '', 0]) {
        final xml = _render('sabily', {'iconBackground': bad}, 'res/values/colors.xml');
        expect(xml, isNot(contains('brand_icon_background')), reason: 'value $bad');
      }
    });
  });

  group('present: emitted once and referenced', () {
    test('colors.xml gains the colour, and keeps the splash colour', () {
      final xml = _render('sabily', {'iconBackground': '#2f3b4f'}, 'res/values/colors.xml');
      expect(xml, contains('<color name="brand_icon_background">#2f3b4f</color>'));
      expect(xml, contains('brand_splash_background'),
          reason: 'the launch window keeps its own colour');
    });

    test('the adaptive icon points at it instead', () {
      final xml =
          _render('sabily', {'iconBackground': '#2f3b4f'}, 'mipmap-anydpi-v26/ic_launcher.xml');
      expect(xml, contains('<background android:drawable="@color/brand_icon_background" />'));
    });

    test('the launch window is NOT repointed', () {
      // The whole point: the icon moves, the entry does not.
      final launch = _render('sabily', {'iconBackground': '#2f3b4f'}, 'drawable/launch_background.xml');
      expect(launch, contains('@color/brand_splash_background'));
      expect(launch, isNot(contains('brand_icon_background')));

      final styles = _render('sabily', {'iconBackground': '#2f3b4f'}, 'values-v31/styles.xml');
      expect(styles, isNot(contains('brand_icon_background')));
    });
  });

  group('what eSimple actually ships', () {
    test('navy icon, black entry', () {
      final logo = _brand('esimple')['logo'] as Map<String, dynamic>;
      expect(logo['iconBackground'], '#2f3b4f');
      expect(logo['introBackground'], '#000000',
          reason: 'the splash and the intro video stay black');

      final colors =
          File('android/app/src/esimple/res/values/colors.xml').readAsStringSync();
      expect(colors, contains('<color name="brand_splash_background">#000000</color>'));
      expect(colors, contains('<color name="brand_icon_background">#2f3b4f</color>'));

      final icon =
          File('android/app/src/esimple/res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
      expect(icon, contains('@color/brand_icon_background'));

      final launch =
          File('android/app/src/esimple/res/drawable/launch_background.xml').readAsStringSync();
      expect(launch, contains('@color/brand_splash_background'),
          reason: 'the launch window is untouched');
    });

    test('the other brands set nothing', () {
      for (final slug in ['sabily', 'acorn']) {
        final logo = _brand(slug)['logo'] as Map<String, dynamic>;
        expect(logo.containsKey('iconBackground'), isFalse, reason: slug);
        expect(File('android/app/src/$slug/res/values/colors.xml').readAsStringSync(),
            isNot(contains('brand_icon_background')),
            reason: slug);
      }
    });

    test('BrandConfig reads it, and tolerates its absence', () {
      final parsed = BrandConfig.parse(_brand('esimple'), expectedSlug: 'esimple');
      expect(parsed.errors, isEmpty);
      final config = parsed.config as BrandConfig;
      expect(config.logo.iconBackground, isNotNull);
      expect(config.logo.introBackground, isNotNull);

      final sabily = BrandConfig.parse(_brand('sabily'), expectedSlug: 'sabily');
      expect(sabily.errors, isEmpty);
      expect((sabily.config as BrandConfig).logo.iconBackground, isNull);
    });
  });
}

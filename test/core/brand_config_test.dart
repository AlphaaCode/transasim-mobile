import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_validation.dart';

/// A configuration with every required field present, used as the baseline
/// that individual tests then break in one specific way.
Map<String, dynamic> validJson() => <String, dynamic>{
      'slug': 'acme',
      'name': 'Acme',
      'colors': {
        'primary': '#003c3a',
        'accent': '#d2f5ec',
        'surface': '#f9f2d3',
        'cta': '#fadb14',
        'ctaText': '#003c3a',
      },
      'logo': {'mark': 'm.png', 'full': 'f.png', 'fullInverse': 'fi.png'},
      'locales': ['fr', 'en'],
      'defaultLocale': 'fr',
      'currency': 'EUR',
      'support': {'email': 'contact@acme.test'},
      'legal': {
        'companyName': 'Acme SA',
        'country': 'FR',
        'termsUrl': 'https://acme.test/terms',
        'privacyUrl': 'https://acme.test/privacy',
        'vatRate': 20.0,
      },
      // Explicitly dynamic: tests replace `registration` with a nested map, and
      // inference would otherwise pin this to Map<String, String>.
      'mobile': <String, dynamic>{
        'applicationId': 'com.acme.esim',
        'bundleIdentifier': 'com.acme.esim',
        'displayName': 'Acme',
        'deepLinkScheme': 'acme',
        'apiBaseUrl': 'https://api.acme.test/api',
        'stripePublishableKey': 'pk_test_123',
      },
    };

BrandValidation parse(Map<String, dynamic> json, {String slug = 'acme'}) =>
    BrandConfig.parse(json, expectedSlug: slug);

void main() {
  group('a complete configuration', () {
    test('is accepted with no errors', () {
      final r = parse(validJson());
      expect(r.errors, isEmpty, reason: r.describe('acme'));
      expect(r.isUsable, isTrue);
      expect(r.config, isA<BrandConfig>());
    });

    test('exposes the five colour roles', () {
      final c = parse(validJson()).config as BrandConfig;
      // Roles, not hues: the test names the role and never the colour.
      expect(c.colors.primary.toARGB32(), 0xFF003C3A);
      expect(c.colors.cta.toARGB32(), 0xFFFADB14);
      expect(c.colors.ctaText.toARGB32(), 0xFF003C3A);
    });
  });

  group('validation reports EVERY problem in one pass', () {
    // The requirement from §2.10: an integrator fixes their config in one go,
    // not in ten. This is the test that keeps that true.
    test('four missing required fields produce four named errors', () {
      final json = validJson()
        ..remove('name')
        ..remove('currency')
        ..remove('defaultLocale');
      (json['colors'] as Map).remove('cta');

      final r = parse(json);
      final fields = r.errors.map((e) => e.field).toSet();

      expect(fields, containsAll(<String>['name', 'currency', 'defaultLocale', 'colors.cta']));
      expect(r.errors.length, greaterThanOrEqualTo(4));
      expect(r.config, isNull);
    });
  });

  group('cross-field rules', () {
    test('slug must equal the folder name', () {
      final r = parse(validJson(), slug: 'not-acme');
      expect(r.errors.map((e) => e.field), contains('slug'));
    });

    test('defaultLocale must be one of locales', () {
      final json = validJson()..['defaultLocale'] = 'de';
      final r = parse(json);
      expect(r.errors.map((e) => e.field), contains('defaultLocale'));
    });

    test('a language the socle cannot render is a warning, not an error', () {
      final json = validJson()..['locales'] = ['fr', 'xx'];
      final r = parse(json);
      expect(r.isUsable, isTrue, reason: 'the brand still works in fr');
      expect(r.warnings.map((w) => w.field), contains('locales'));
    });
  });

  group('the Stripe key guard', () {
    // §2.9 and brief §4.4: a live sk_ key has already been found sitting in a
    // dev environment once. Two lines of validation beat an irreversible
    // incident in a published app.
    test('a secret key is refused, and the message says why', () {
      final json = validJson();
      (json['mobile'] as Map)['stripePublishableKey'] = 'sk_live_abc';
      final r = parse(json);

      final err = r.errors.firstWhere((e) => e.field == 'mobile.stripePublishableKey');
      expect(err.reason, contains('SECRET'));
      expect(r.config, isNull);
    });

    test('anything that is not pk_ is refused', () {
      final json = validJson();
      (json['mobile'] as Map)['stripePublishableKey'] = 'whatever';
      final r = parse(json);
      expect(r.errors.map((e) => e.field), contains('mobile.stripePublishableKey'));
    });
  });

  group('the feature-flag hygiene rule', () {
    // Brief §2.5 / §7.6: nothing enters `features` unless the code reads it.
    test('wallet defaults to off when absent', () {
      final c = parse(validJson()).config as BrandConfig;
      expect(c.features.wallet, isFalse);
    });

    test('an unknown flag warns that nothing reads it', () {
      final json = validJson()..['features'] = {'b2b': true, 'wallet': false};
      final r = parse(json);
      expect(r.isUsable, isTrue);
      final w = r.warnings.firstWhere((w) => w.field == 'features.b2b');
      expect(w.reason, contains('no code reads it'));
    });
  });

  group('RTL artwork', () {
    test('a brand serving Arabic without RTL artwork is warned', () {
      final json = validJson()
        ..['locales'] = ['fr', 'ar']
        ..['visuals'] = {
          'howItWorks': {'ltr': 'hiw.png'}
        };
      final r = parse(json);
      expect(r.isUsable, isTrue);
      expect(
        r.warnings.map((w) => w.field),
        contains('visuals.howItWorks.rtl'),
      );
    });

    test('a brand not serving Arabic is not warned', () {
      final json = validJson()
        ..['visuals'] = {
          'howItWorks': {'ltr': 'hiw.png'}
        };
      final r = parse(json);
      expect(r.warnings.map((w) => w.field), isNot(contains('visuals.howItWorks.rtl')));
    });
  });

  group('legal identity', () {
    test('country has no default — it must be stated', () {
      final json = validJson();
      (json['legal'] as Map).remove('country');
      final r = parse(json);
      expect(r.errors.map((e) => e.field), contains('legal.country'));
    });

    test('missing identifiers are shown as a dash, never invented', () {
      final c = parse(validJson()).config as BrandConfig;
      expect(c.legal.siren, isNull);
      expect(BrandLegal.show(c.legal.siren), '—');
      expect(BrandLegal.show('552120222'), '552120222');
    });

    test('legal texts must be URLs, so they change without a store submission', () {
      final json = validJson();
      (json['legal'] as Map)['termsUrl'] = 'assets/terms-fr.pdf';
      final r = parse(json);
      expect(r.errors.map((e) => e.field), contains('legal.termsUrl'));
    });
  });

  group('registration fields', () {
    test('an unknown field id is ignored with a warning, not an error', () {
      final json = validJson();
      (json['mobile'] as Map)['registration'] = {
        'fields': ['email', 'password', 'favouriteColour']
      };
      final r = parse(json);
      expect(r.isUsable, isTrue);
      expect(r.warnings.map((w) => w.field), contains('mobile.registration.fields'));
      expect(
        (r.config as BrandConfig).mobile.registrationFields,
        <String>['email', 'password'],
      );
    });

    test('an account cannot be created without email and password', () {
      final json = validJson();
      (json['mobile'] as Map)['registration'] = {
        'fields': ['firstName']
      };
      final r = parse(json);
      expect(r.errors.map((e) => e.field), contains('mobile.registration.fields'));
    });
  });

  group('no path in the codebase carries a client slug', () {
    test('asset paths are built from the active brand, never written literally', () {
      final c = parse(validJson()).config as BrandConfig;
      expect(c.assetPath(c.logo.full), 'brands/acme/assets/f.png');
    });
  });

  group('the shipped Sabily configuration', () {
    test('parses, and any warnings are listed so they are a decision', () {
      final file = File('brands/sabily/brand.json');
      expect(file.existsSync(), isTrue, reason: 'brands/sabily/brand.json must exist');

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final r = BrandConfig.parse(json, expectedSlug: 'sabily');

      expect(r.errors, isEmpty, reason: r.describe('sabily'));

      final c = r.config as BrandConfig;
      expect(c.locales.length, 7, reason: 'Sabily serves seven languages');
      expect(c.defaultLocale, 'fr');
      expect(c.servesRtl, isTrue, reason: 'Arabic is served, so RTL must be exercised');
      // The published Android identity is frozen (ARCHITECTURE-MOBILE §3.2).
      expect(c.mobile.applicationId, 'com.sabily.esim');
    });
  });
}

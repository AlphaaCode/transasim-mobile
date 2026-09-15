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
  _stepsSuite();
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

  group('pack header images', () {
    test('a country override wins, then its region, then world', () {
      final json = validJson();
      (json['visuals'] as Map? ?? (json['visuals'] = <String, dynamic>{}))['packImages'] = {
        'mena': 'm.jpg',
        'world': 'w.jpg',
        'TUR': 't.jpg',
      };
      final c = parse(json).config as BrandConfig;
      expect(c.visuals.packImage(destinationCode: 'tur', regionKey: 'asia'), 't.jpg');
      expect(c.visuals.packImage(destinationCode: 'SAU', regionKey: 'mena'), 'm.jpg');
      expect(c.visuals.packImage(destinationCode: 'JPN', regionKey: 'asia'), 'w.jpg');
    });

    test('an unknown key is reported and ignored', () {
      final json = validJson();
      (json['visuals'] as Map? ?? (json['visuals'] = <String, dynamic>{}))['packImages'] = {
        'narnia': 'n.jpg',
      };
      final r = parse(json);
      expect(r.warnings.map((w) => w.field), contains('visuals.packImages.narnia'));
      expect((r.config as BrandConfig).visuals.packImages, isEmpty);
    });

    test('no images configured keeps the plain wash', () {
      final c = parse(validJson()).config as BrandConfig;
      expect(c.visuals.packImage(destinationCode: 'FRA', regionKey: 'europe'), isNull);
    });

    test('every image Sabily names is bundled', () {
      final raw = jsonDecode(File('brands/sabily/brand.json').readAsStringSync());
      final c = BrandConfig.parse(raw as Map<String, dynamic>, expectedSlug: 'sabily').config
          as BrandConfig;
      expect(c.visuals.packImages.keys, containsAll(['mena', 'europe', 'world', 'TUR']));
      for (final file in c.visuals.packImages.values) {
        expect(File('brands/sabily/assets/$file').existsSync(), isTrue, reason: file);
      }
    });
  });

  group('theme.shop', () {
    test('absent: no shop overrides, so every shop screen keeps its rendering', () {
      expect((parse(validJson()).config as BrandConfig).theme.shop, isEmpty);
    });

    test('known roles are read; an unknown one warns and a bad colour is an error', () {
      final json = validJson();
      json['theme'] = {
        'shop': {'fill': '#49cdd2', 'glow': '#ffffff', 'display': 'cyan'},
      };
      final r = parse(json);
      expect(r.warnings.map((w) => w.field), contains('theme.shop.glow'));
      expect(r.errors.map((e) => e.field), contains('theme.shop.display'));
    });
  });

  group('the partner programme link', () {
    test('is optional: a brand without one has no partner entry', () {
      final c = parse(validJson()).config as BrandConfig;
      expect(c.support.partnerUrl, isNull);
    });

    test('must be https when present', () {
      final json = validJson();
      (json['support'] as Map)['partnerUrl'] = 'http://acme.test/partners';
      expect(parse(json).errors.map((e) => e.field), contains('support.partnerUrl'));
    });

    test('Sabily opens its own partner page', () {
      final raw = jsonDecode(File('brands/sabily/brand.json').readAsStringSync());
      final c = BrandConfig.parse(raw as Map<String, dynamic>, expectedSlug: 'sabily').config as BrandConfig;
      expect(c.support.partnerUrl, 'https://sabily.fr/en/devenir-partenaire');
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
        'fields': [...kUserRequiredRegistrationFields, 'favouriteColour']
      };
      final r = parse(json);
      expect(r.isUsable, isTrue, reason: r.describe('acme'));
      expect(r.warnings.map((w) => w.field), contains('mobile.registration.fields'));
      expect(
        (r.config as BrandConfig).mobile.registrationFields,
        kUserRequiredRegistrationFields,
        reason: 'the unknown id is dropped, the rest kept in order',
      );
    });

    test('a config missing a server-required field is refused, and says which', () {
      // Brief §8.4 warns the live backend wants eleven fields and that the
      // request to cut it to four is filed, not shipped. A brand configured for
      // the wished-for set would 400 on every sign-up; that is caught here
      // instead, at parse time.
      final json = validJson();
      (json['mobile'] as Map)['registration'] = {
        'fields': ['email', 'password', 'firstName', 'lastName']
      };
      final r = parse(json);

      final err = r.errors.firstWhere((e) => e.field == 'mobile.registration.fields');
      for (final missing in ['dateOfBirth', 'address', 'zipCode', 'city', 'country']) {
        expect(err.reason, contains(missing));
      }
      expect(r.config, isNull);
    });

    test('the eleven the server demands, and the nine a person types', () {
      expect(kServerRequiredRegistrationFields.length, 11);
      // language and title are supplied by the app, not typed by anyone.
      expect(kUserRequiredRegistrationFields.length, 9);
      expect(kUserRequiredRegistrationFields, isNot(contains('language')));
      expect(kUserRequiredRegistrationFields, isNot(contains('title')));
      expect(kUserRequiredRegistrationFields, contains('dateOfBirth'));
    });

    test('password rules mirror the deployed constraints exactly', () {
      // @Size(min 8) + @Pattern(lower, upper, special). No digit requirement:
      // matching the server matters more than matching a habit.
      expect(kPasswordMinLength, 8);
      expect(kPasswordPattern.hasMatch('Passw0rd!'), isTrue);
      expect(kPasswordPattern.hasMatch('NoSpecial1'), isFalse, reason: 'needs a special char');
      expect(kPasswordPattern.hasMatch('nouppercase!'), isFalse);
      expect(kPasswordPattern.hasMatch('NOLOWERCASE!'), isFalse);
      expect(kPasswordPattern.hasMatch('Abcdefg!'), isTrue, reason: 'no digit required');
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

void _stepsSuite() {
  // registration.steps GROUPS fields that registration.fields already declared.
  // Every check here exists because a mis-grouped step fails exactly the way a
  // short field list does: silently, at sign-up, with a 400.

  Map<String, dynamic> withSteps(Object? steps, {List<String>? fields}) {
    final json = validJson();
    (json['mobile'] as Map)['registration'] = <String, dynamic>{
      'fields': fields ?? [...kUserRequiredRegistrationFields, 'phoneNum'],
      'steps': ?steps,
    };
    return json;
  }

  BrandValidation parse(Object? steps, {List<String>? fields}) =>
      BrandConfig.parse(withSteps(steps, fields: fields), expectedSlug: 'acme');

  group('registration.steps', () {
    test('absent means one page, which is the old behaviour exactly', () {
      final r = parse(null);
      expect(r.errors, isEmpty);
      expect((r.config as BrandConfig).mobile.registrationSteps, isEmpty);
    });

    test('a valid split is kept in order', () {
      final r = parse([
        {'title': 'a', 'fields': ['firstName', 'lastName', 'email', 'phoneNum']},
        {'title': 'b', 'fields': ['password']},
        {'title': 'c', 'fields': ['dateOfBirth', 'address', 'zipCode', 'city', 'country']},
      ]);
      expect(r.errors, isEmpty, reason: r.describe('acme'));

      final steps = (r.config as BrandConfig).mobile.registrationSteps;
      expect(steps.map((s) => s.titleKey), <String>['a', 'b', 'c']);
      expect(steps.first.fields, <String>['firstName', 'lastName', 'email', 'phoneNum']);
    });

    test('a field no step shows is an error, not a quietly missing input', () {
      // The whole reason the check exists: the user is never asked for it and
      // the server still demands it.
      final r = parse([
        {'title': 'a', 'fields': ['firstName', 'lastName', 'email', 'phoneNum']},
        {'title': 'b', 'fields': ['password']},
      ]);
      final err = r.errors.firstWhere((e) => e.field == 'mobile.registration.steps');
      expect(err.reason, contains('dateOfBirth'));
      expect(err.reason, contains('country'));
    });

    test('a step cannot introduce a field the config never declared', () {
      final r = parse([
        {'title': 'a', 'fields': [...kUserRequiredRegistrationFields, 'phoneNum', 'nickname']},
      ]);
      expect(r.errors.map((e) => e.reason).join(), contains('nickname'));
    });

    test('the same field on two steps is refused', () {
      final r = parse([
        {'title': 'a', 'fields': ['email', 'firstName', 'lastName', 'phoneNum', 'password']},
        {'title': 'b', 'fields': ['email', 'dateOfBirth', 'address', 'zipCode', 'city', 'country']},
      ]);
      expect(r.errors.map((e) => e.reason).join(), contains('more than one step'));
    });

    test('a step with no title is refused', () {
      final r = parse([
        {'fields': [...kUserRequiredRegistrationFields, 'phoneNum']},
      ]);
      expect(r.errors.map((e) => e.field).join(), contains('steps[0].title'));
    });

    test('an empty step warns and is dropped rather than rendering blank', () {
      final r = parse([
        {'title': 'a', 'fields': <String>[]},
        {'title': 'b', 'fields': [...kUserRequiredRegistrationFields, 'phoneNum']},
      ]);
      expect(r.errors, isEmpty, reason: r.describe('acme'));
      expect(r.warnings.map((w) => w.reason).join(), contains('no fields'));
      expect((r.config as BrandConfig).mobile.registrationSteps.length, 1);
    });

    test('steps change no requirement — the server list is untouched', () {
      // Grouping is display. What the backend demands is decided elsewhere and
      // must stay decided elsewhere.
      final grouped = parse([
        {'title': 'a', 'fields': ['firstName', 'lastName', 'email', 'phoneNum']},
        {'title': 'b', 'fields': ['password']},
        {'title': 'c', 'fields': ['dateOfBirth', 'address', 'zipCode', 'city', 'country']},
      ]).config as BrandConfig;
      final flat = parse(null).config as BrandConfig;

      expect(grouped.mobile.registrationFields, flat.mobile.registrationFields);
      expect(
        grouped.mobile.registrationSteps.expand((s) => s.fields).toSet(),
        flat.mobile.registrationFields.toSet(),
      );
    });

    test("the shipped config's steps cover every field it declares", () {
      // Guards the real brands/sabily/brand.json, not a fixture.
      final json = jsonDecode(File('brands/sabily/brand.json').readAsStringSync())
          as Map<String, dynamic>;
      final r = BrandConfig.parse(json, expectedSlug: 'sabily');
      expect(r.errors, isEmpty, reason: r.describe('sabily'));

      final config = r.config as BrandConfig;
      expect(config.mobile.registrationSteps, isNotEmpty);
      expect(
        config.mobile.registrationSteps.expand((s) => s.fields).toSet(),
        config.mobile.registrationFields.toSet(),
      );
    });
  });
}

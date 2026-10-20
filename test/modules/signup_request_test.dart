/// What the sign-up sends, and what it says when the server refuses.
///
/// The form has no phone field, on purpose. The backend still wants the key:
/// `"phoneNum": null` and an absent key both make it look up every phone-less
/// subscriber and answer HTTP 500 (verified 20/10/2026), while `""` is stored
/// as "no phone". So the request carries `"phoneNum": ""`, always, and the
/// first group here holds that down. The rest pins the password rule, each
/// thing the server says about a refused sign-up, and the platform an install
/// announces.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/l10n.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/result/result.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/modules/account/data/account_repository_impl.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';

import '../core/brand_config_test.dart' show validJson;
import '../core/session_test.dart' show SpyStorage;
import 'account_test.dart' show FakeWire, filledDraft, repoOn;

/// A brand that serves every language, so the strings can be checked in all.
BrandConfig _brand() {
  final json = validJson()
    ..['locales'] = kSocleSupportedLanguages
    ..['defaultLocale'] = kSocleSupportedLanguages.first;
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

void main() {
  FieldSpec spec(String id) => kFieldSpecs[id]!;

  group('the register request always carries "phoneNum": ""', () {
    /// The body as the server receives it, after JSON encoding.
    Future<Map<String, dynamic>> sent(RegistrationDraft draft) async {
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).register(draft, language: 'fr');
      expect(wire.sent, hasLength(1));
      return jsonDecode(jsonEncode(wire.last.data)) as Map<String, dynamic>;
    }

    // What the real form produces: nobody is asked for a phone number, so the
    // draft never has one.
    final untouched = RegistrationDraft(
      email: 'a@b.test',
      password: 'Abcdefg!',
      firstName: 'Ada',
      lastName: 'Lovelace',
    );

    test('the key is there and its value is the empty string, not null', () async {
      final body = await sent(untouched);
      expect(body.containsKey('phoneNum'), isTrue, reason: 'an absent key is a 500');
      expect(body['phoneNum'], isNotNull, reason: 'null is a 500');
      expect(body['phoneNum'], '');
    });

    test('it is in the JSON text itself, not only in the map', () async {
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).register(untouched, language: 'fr');
      expect(jsonEncode(wire.last.data), contains('"phoneNum":""'));
    });

    test('a missing phone neither throws nor blocks the request', () async {
      final wire = FakeWire(body: <String, dynamic>{});
      await expectLater(repoOn(wire).register(untouched, language: 'fr'), completes);
      expect(wire.sent, hasLength(1));
      expect(wire.last.path, '/v1/subscribers/register');
    });

    test('whatever the draft holds, the empty string is what goes', () async {
      final body = await sent(filledDraft()); // this one has a phone in it
      expect(body['phoneNum'], '');
    });
  });

  group('the password is held to the server rule before anything is sent', () {
    test('the rule is the deployed one, character for character', () {
      expect(kPasswordPattern.pattern, r'^(?=.*[a-z])(?=.*[A-Z])(?=.*[^a-zA-Z0-9]).*$');
      expect(kPasswordMinLength, 8);
    });

    test('what is refused, and which message it earns', () {
      const cases = <String, String?>{
        '': 'account.error.required',
        'Abcdef!': 'account.error.passwordShort', // seven
        'abcdefg!': 'account.error.passwordWeak', // no capital
        'ABCDEFG!': 'account.error.passwordWeak', // no lower case
        'Abcdefgh': 'account.error.passwordWeak', // no symbol
        'Abcdefg1': 'account.error.passwordWeak', // a digit is not a symbol
        'Abcdefg!': null,
        'Abcde fg': null, // a space is not alphanumeric, and the server accepts it
        'Zz9!zzzz': null,
      };
      cases.forEach((password, key) {
        expect(validateField(spec('password'), password), key, reason: '"$password"');
      });
    });
  });

  group('what the server says about a refused sign-up', () {
    AuthFailed said(AppError e) => registrationFailure(AccountFailure(e));

    test('the e-mail already has an account — all three keys the backend uses', () {
      for (final code in const ['error.userexists', 'error.emailexists', 'error.idexists']) {
        expect(said(HttpFailure(400, serverCode: code)).messageKey, 'account.error.emailTaken',
            reason: code);
      }
    });

    test('the e-mail domain is not accepted', () {
      final f = said(const HttpFailure(400, serverCode: 'error.emaildomainnotallowed'));
      expect(f.messageKey, 'account.error.emailDomain');
    });

    test("a validation failure keeps the server's wording for each field", () {
      final f = said(const HttpFailure(
        400,
        serverCode: 'error.validation',
        fieldErrors: {'password': 'Password must be longer than 7 characters'},
      ));
      expect(f.messageKey, 'account.error.checkFields');
      expect(f.fieldErrors, {'password': 'Password must be longer than 7 characters'});
    });

    test('a named condition outranks the field list that came with it', () {
      final f = said(const HttpFailure(
        400,
        serverCode: 'error.emailexists',
        fieldErrors: {'email': 'anything'},
      ));
      expect(f.messageKey, 'account.error.emailTaken');
      expect(f.fieldErrors, isEmpty);
    });

    test('a 400 nothing is known about is the generic line, not a guess', () {
      expect(said(const HttpFailure(400, serverCode: 'error.something.new')).messageKey,
          'error.generic');
      expect(said(const HttpFailure(500)).messageKey, 'error.generic');
    });

    test('the phone-number message is gone: the app never asks for a phone', () {
      final f = said(const HttpFailure(400, serverCode: 'error.subscriber phone number exists'));
      expect(f.messageKey, 'error.generic');
    });

    test('no connection is still no connection', () {
      expect(said(const NetworkUnavailable('timeout')).messageKey, 'error.network_unavailable');
    });

    test('every sentence exists in every language, and none is blank', () {
      final brand = _brand();
      for (final key in const [
        'account.error.emailTaken',
        'account.error.emailDomain',
        'account.error.checkFields',
        'account.error.badCredentials',
      ]) {
        for (final code in kSocleSupportedLanguages) {
          final text = L10n(brand: brand, language: code).t(key);
          expect(text, isNot(key), reason: '$code is missing $key');
          expect(text.trim(), isNotEmpty, reason: '$code has $key empty');
        }
      }
    });

    test('the English wording is the one that was asked for', () {
      final en = L10n(brand: _brand(), language: 'en');
      expect(en.t('account.error.emailTaken'),
          'This e-mail already has an account. Log in or reset your password.');
      expect(en.t('account.error.emailDomain'), 'This e-mail domain is not accepted');
      expect(en.t('account.error.checkFields'), 'Please check the highlighted fields');
      expect(en.t('account.error.badCredentials'), 'Wrong e-mail or password');
    });
  });

  group('the answer as it arrives over the wire', () {
    Future<AccountFailure> refused(Object body) async {
      final wire = FakeWire(status: 400, body: body);
      try {
        await repoOn(wire).register(filledDraft(), language: 'fr');
      } on AccountFailure catch (e) {
        return e;
      }
      fail('a 400 must not look like a success');
    }

    test('"already has an account" is read from the backend\'s own message', () async {
      for (final code in const ['error.userexists', 'error.emailexists', 'error.idexists']) {
        final e = await refused(<String, dynamic>{'message': code});
        expect(e.isDuplicateAccount, isTrue, reason: code);
        expect(registrationFailure(e).messageKey, 'account.error.emailTaken', reason: code);
      }
    });

    test('fieldErrors is parsed: first message per field, junk skipped', () async {
      final e = await refused(<String, dynamic>{
        'title': 'Method argument not valid',
        'status': 400,
        'message': 'error.validation',
        'fieldErrors': [
          {'objectName': 'subscriberModel', 'field': 'password', 'message': 'Too short'},
          {'objectName': 'subscriberModel', 'field': 'password', 'message': 'Too weak'},
          {'objectName': 'subscriberModel', 'field': 'email', 'message': 'Not an address'},
          'not a map',
          {'field': '', 'message': 'no field named'},
          {'field': 'city'},
        ],
      });
      final http = e.error as HttpFailure;
      expect(http.fieldErrors, {'password': 'Too short', 'email': 'Not an address'});
      expect(registrationFailure(e).messageKey, 'account.error.checkFields');
    });

    test('a 400 with no fieldErrors has none', () async {
      final e = await refused(<String, dynamic>{'message': 'error.userexists'});
      expect((e.error as HttpFailure).fieldErrors, isEmpty);
    });
  });

  group('a wrong password at sign-in reads "Wrong e-mail or password"', () {
    test('a 401 from /authenticate is bad credentials, not an expired session', () async {
      final wire = FakeWire(status: 401, body: <String, dynamic>{'status': 401});
      Object? failure;
      try {
        await repoOn(wire).signIn(email: 'a@b.test', password: 'Wrong1!pw');
      } on AccountFailure catch (e) {
        failure = e;
      }
      expect(failure, isA<AccountFailure>());
      expect((failure as AccountFailure).isBadCredentials, isTrue);
      expect(wire.last.path, '/authenticate');
    });

    test('end to end: the controller turns it into the sentence the person reads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final brand = _brand();
      final wire = FakeWire(status: 401, body: <String, dynamic>{'status': 401});
      final c = ProviderContainer(overrides: [
        accountRepositoryProvider.overrideWithValue(repoOn(wire)),
        brandConfigProvider.overrideWithValue(brand),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionStoreProvider.overrideWithValue(SessionStore(storage: SpyStorage())),
      ]);
      addTearDown(c.dispose);

      await c.read(authControllerProvider.notifier).signIn('a@b.test', 'Wrong1!pw');

      final state = c.read(authControllerProvider) as AuthFailed;
      expect(state.messageKey, 'account.error.badCredentials');
      expect(L10n(brand: brand, language: 'en').t(state.messageKey), 'Wrong e-mail or password');
    });
  });

  group('the platform an install announces', () {
    // The literal 'ANDROID' was on both calls, so an iOS install said it was
    // Android when it signed up and again when it activated.
    setUp(() => debugDefaultTargetPlatformOverride = null);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    const names = <TargetPlatform, String>{
      TargetPlatform.android: 'ANDROID',
      TargetPlatform.iOS: 'IOS',
    };

    for (final MapEntry(key: platform, value: name) in names.entries) {
      test('sign-up on $platform says $name', () async {
        debugDefaultTargetPlatformOverride = platform;
        final wire = FakeWire(body: <String, dynamic>{});
        await repoOn(wire).register(filledDraft(), language: 'fr');
        expect((wire.last.data as Map<String, dynamic>)['platform'], name);
      });

      test('activation on $platform says $name', () async {
        debugDefaultTargetPlatformOverride = platform;
        final wire = FakeWire(body: <String, dynamic>{});
        await repoOn(wire).verify(email: 'a@b.test', code: '123456');
        expect(wire.last.method, 'PUT');
        expect(wire.last.queryParameters['platform'], name);
      });
    }
  });
}

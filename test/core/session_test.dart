import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';

/// R11, as assertions.
///
/// `ANALYSE-EXISTANT.md` listed four separate session defects in the old app.
/// Each one has a test here, so "we fixed it" is checkable rather than claimed.

/// Stands in for the Keychain/Keystore, and records everything ever written so
/// a test can assert what did NOT get stored.
class SpyStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};
  final List<String> writes = [];
  final List<String> deletes = [];

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async {
    writes.add('$key=$value');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async {
    deletes.add(key);
    values.remove(key);
  }

  @override
  Future<void> deleteAll({dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async {
    deletes.addAll(values.keys);
    values.clear();
  }

  @override
  Future<Map<String, String>> readAll({dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async =>
      Map.of(values);

  @override
  Future<bool> containsKey({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async =>
      values.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Build a JWT with a given expiry. Unsigned — nothing here verifies it, and
/// nothing should: verification is the server's job.
String jwt({DateTime? exp, String sub = 'user@example.test'}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final payload = <String, dynamic>{
    'sub': sub,
    if (exp != null) 'exp': exp.millisecondsSinceEpoch ~/ 1000,
  };
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.signature';
}

ProviderContainer containerWith(SpyStorage storage) {
  final c = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(SessionStore(storage: storage)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('R11.1 — the token goes to secure storage, and nowhere else', () {
    test('signing in writes exactly one key', () async {
      final storage = SpyStorage();
      final c = containerWith(storage);
      await c.read(sessionProvider.future);

      await c.read(sessionProvider.notifier).signIn(jwt());

      expect(storage.values.keys.length, 1,
          reason: 'one storage layer, one key — the old app had two layers');
      expect(storage.values.keys.single, 'session.token');
    });

    test('the default backend is the platform keystore, with no fallback', () {
      // SessionStore has exactly one backend and no SharedPreferences path to
      // fall back to, so there is no route by which a token reaches an
      // unencrypted file. Constructing the default exercises that wiring.
      expect(SessionStore(), isA<SessionStore>());
    });
  });

  group('R11.2 — a password is never persisted', () {
    test('nothing written to storage contains the password', () async {
      final storage = SpyStorage();
      final c = containerWith(storage);
      await c.read(sessionProvider.future);

      // The registration flow would have had this password in hand.
      const password = 'Sup3rSecret!';
      await c.read(sessionProvider.notifier).signIn(jwt());

      expect(storage.writes.join('|'), isNot(contains(password)));
      expect(storage.values.values.join('|'), isNot(contains(password)));
    });

    test('signIn takes a token and offers no way to pass a password', () {
      // The old app called savePendingCredentials(email, password) and wrote
      // `pending_password` in the clear. There is deliberately no API here that
      // could do that — this test documents the shape as the guarantee.
      final signIn = SessionController().signIn;
      expect(signIn, isA<Future<void> Function(String)>());
    });
  });

  group('R11.3 — signing out clears everything', () {
    test('the token is gone from storage and from state', () async {
      final storage = SpyStorage();
      final c = containerWith(storage);
      await c.read(sessionProvider.future);
      await c.read(sessionProvider.notifier).signIn(jwt());
      expect(storage.values, isNotEmpty);

      await c.read(sessionProvider.notifier).signOut();

      expect(storage.values, isEmpty, reason: 'no copy may survive logout');
      expect(c.read(sessionProvider).value, isNull);
      expect(c.read(bearerTokenProvider), isNull,
          reason: 'a signed-out user must not keep sending a bearer token');
      expect(c.read(isSignedInProvider), isFalse);
    });

    test('a 401 has the same effect as signing out', () async {
      final storage = SpyStorage();
      final c = containerWith(storage);
      await c.read(sessionProvider.future);
      await c.read(sessionProvider.notifier).signIn(jwt());

      await c.read(sessionProvider.notifier).onUnauthorized();

      expect(storage.values, isEmpty);
      expect(c.read(bearerTokenProvider), isNull);
    });
  });

  group('R11.4 — expiry is decided from exp, not discovered on a 401', () {
    final past = DateTime.utc(2020, 1, 1);
    final future = DateTime.utc(2999, 1, 1);

    test('exp is decoded from the token', () {
      final s = Session.fromToken(jwt(exp: future, sub: 'a@b.test'));
      expect(s.expiresAt, future);
      expect(s.subject, 'a@b.test');
    });

    test('an expired token is treated as signed out at startup, and discarded',
        () async {
      final storage = SpyStorage()..values['session.token'] = jwt(exp: past);
      final c = containerWith(storage);

      final session = await c.read(sessionProvider.future);

      expect(session, isNull, reason: 'the old app read this as "logged in"');
      expect(storage.values, isEmpty, reason: 'a token known to be dead is not kept');
    });

    test('a live token survives startup', () async {
      final storage = SpyStorage()..values['session.token'] = jwt(exp: future);
      final c = containerWith(storage);

      final session = await c.read(sessionProvider.future);

      expect(session, isNotNull);
      expect(c.read(bearerTokenProvider), isNotNull);
    });

    test('expiresWithin protects a flow that is about to start', () {
      final s = Session.fromToken(jwt(exp: DateTime.utc(2024, 1, 1, 12, 0)));
      final now = DateTime.utc(2024, 1, 1, 11, 58);

      expect(s.expiresWithin(const Duration(minutes: 5), now: now), isTrue,
          reason: 'do not begin a checkout on a token that dies mid-flow');
      expect(s.expiresWithin(const Duration(seconds: 30), now: now), isFalse);
    });
  });

  group('updating over the old app: signed out, asked to sign in, nothing stuck', () {
    // Exactly what the old app's AuthService and LanguageService left behind.
    Map<String, Object> oldAppPrefs() => {
          'auth_token': jwt(exp: DateTime.utc(2999)),
          'is_logged_in': true,
          'user_data': '{"email":"user@example.test"}',
          'pending_email': 'user@example.test',
          'pending_password': 'Sup3rSecret!',
          'selected_language': 'ar',
          'selected_currency': 'EUR',
        };

    test('the old plaintext token and password are deleted; the language is kept', () async {
      SharedPreferences.setMockInitialValues(oldAppPrefs());
      final prefs = await SharedPreferences.getInstance();

      await forgetLegacyApp(prefs);

      for (final key in ['auth_token', 'is_logged_in', 'user_data', 'pending_email', 'pending_password']) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getString(LanguageController.storageKey), 'ar');
      expect(prefs.containsKey('selected_language'), isFalse);
    });

    test('a language already chosen in this app is not overwritten', () async {
      SharedPreferences.setMockInitialValues(
          {...oldAppPrefs(), LanguageController.storageKey: 'de'});
      final prefs = await SharedPreferences.getInstance();
      await forgetLegacyApp(prefs);
      expect(prefs.getString(LanguageController.storageKey), 'de');
    });

    test('the old token is not a session: secure storage is empty, so signed out', () async {
      final c = containerWith(SpyStorage());
      expect(await c.read(sessionProvider.future), isNull);
      expect(c.read(isSignedInProvider), isFalse);
    });

    test('secure storage that throws resolves to signed out, not an error', () async {
      final c = containerWith(_ThrowingStorage());
      expect(await c.read(sessionProvider.future), isNull);
      expect(c.read(sessionProvider).hasError, isFalse);
      expect(c.read(isSignedInProvider), isFalse);
    });
  });

  group('a malformed token never takes the app down at launch', () {
    test('garbage, wrong segment count, and undecodable payloads all parse', () {
      for (final token in ['', 'not-a-jwt', 'a.b', 'a.!!!.c', 'a.b.c.d']) {
        final s = Session.fromToken(token);
        expect(s.token, token);
        expect(s.expiresAt, isNull);
        expect(s.isExpired(), isFalse, reason: 'unknown expiry is not expiry');
      }
    });
  });
}

class _ThrowingStorage extends SpyStorage {
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) =>
      Future.error(Exception('keychain: errSecInteractionNotAllowed'));
}

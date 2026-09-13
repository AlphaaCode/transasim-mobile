import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/network/api_client.dart';
import 'package:transasim_mobile/core/result/result.dart';
import 'package:transasim_mobile/modules/account/data/account_repository_impl.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';

import '../core/brand_config_test.dart' show validJson;
import '../core/session_test.dart' show SpyStorage;

/// A dio that answers from memory and keeps what it was asked to send, so the
/// wire payload can be asserted without a server.
class FakeWire {
  final List<RequestOptions> sent = <RequestOptions>[];
  int status;
  Object? body;

  FakeWire({this.status = 200, this.body});

  final Dio dio = Dio();

  /// Appended AFTER ApiClient has installed its own interceptor, so the
  /// headers it adds are on the request this captures. Added first, it would
  /// short-circuit before them and every header assertion would pass on an
  /// empty map.
  void arm() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: status,
        data: body,
      ));
    }));
  }

  RequestOptions get last => sent.last;
}

AccountRepositoryImpl repoOn(FakeWire wire, {String? token}) {
  final api = ApiClient(
    baseUrl: 'https://example.test/api',
    token: () => token,
    language: () => 'fr',
    dio: wire.dio,
  );
  wire.arm();
  return AccountRepositoryImpl(api);
}

BrandConfig _brandWithFields(List<String> fields) {
  final json = validJson();
  (json['mobile'] as Map)['registration'] = <String, dynamic>{'fields': fields};
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.config == null) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

const CountryRef france = CountryRef(id: 75, code: 'FR', name: 'France', language: 'fr');

RegistrationDraft filledDraft() => RegistrationDraft(
      email: 'a@b.test',
      password: 'Abcdefg!',
      firstName: 'Ada',
      lastName: 'Lovelace',
      dateOfBirth: DateTime(1815, 12, 10),
      address: '12 rue de la Paix',
      zipCode: '75002',
      city: 'Paris',
      country: france,
      phoneNum: '+33600000000',
    );

/// Unsigned, unverified — enough for `Session.fromToken` to read a subject.
String _jwt(String sub) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${seg({'alg': 'HS256'})}.${seg({'sub': sub, 'exp': exp})}.sig';
}

/// Answers with whichever user is currently signed in, and counts the asking.
class _SwitchableRepository extends FakeRepository {
  String email = 'ada@example.test';
  int fetches = 0;

  @override
  Future<Profile> profile() async {
    fetches++;
    return Profile(id: fetches, email: email);
  }
}

/// Stands in for the network so the controller's state machine can be driven.
class FakeRepository implements AccountRepository {
  Object? failWith;
  String? tokenToReturn = 'jwt';
  RegistrationDraft? registered;
  String? registeredLanguage;
  int resendCalls = 0;

  Never _fail() => throw AccountFailure(failWith! as AppError);

  @override
  Future<String> signIn({required String email, required String password}) async {
    if (failWith != null) _fail();
    return tokenToReturn!;
  }

  @override
  Future<void> register(RegistrationDraft draft, {required String language}) async {
    if (failWith != null) _fail();
    registered = draft;
    registeredLanguage = language;
  }

  @override
  Future<String?> verify({required String email, required String code}) async {
    if (failWith != null) _fail();
    return tokenToReturn;
  }

  @override
  Future<void> resendCode(String email) async {
    resendCalls++;
    if (failWith != null) _fail();
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    if (failWith != null) _fail();
  }

  @override
  Future<Profile> profile() async => const Profile(id: 1, email: 'a@b.test');

  @override
  Future<List<CountryRef>> countries() async => const [france];
}

void main() {
  group('the form collects what the server actually demands', () {
    // The carry-in from the audit: build against the live contract, not the
    // one that has been requested. `SubscriberModel` in the deployed JAR
    // carries eleven @NotNull fields; the reduction to four is filed, not
    // shipped. `brand_config_test.dart` proves a config that omits one is
    // rejected — these prove the form can then render every field it accepts.

    test('every user-required field has a widget spec', () {
      for (final id in kUserRequiredRegistrationFields) {
        expect(kFieldSpecs[id], isNotNull,
            reason: 'a config naming "$id" would pass validation and render nothing');
      }
    });

    test('only phoneNum is optional, and it is not server-required', () {
      final optional = kFieldSpecs.values.where((s) => s.optional).map((s) => s.id);
      expect(optional, <String>['phoneNum']);
      expect(kServerRequiredRegistrationFields, isNot(contains('phoneNum')));
    });

    test('a short list is refused outright — the order test needs the full set', () {
      // Not incidental setup: this is the failure mode the audit turned up.
      // Sabily's own brand.json named six fields against a backend demanding
      // nine from the user, so every sign-up would have 400'd. It is a
      // parse-time error now, which is why the cases below have to pass the
      // whole set before they can say anything about order.
      expect(
        () => _brandWithFields(const ['email', 'password']),
        throwsA(isA<StateError>()),
      );
    });

    test('the brand chooses the order, not the socle', () {
      final reversed = kUserRequiredRegistrationFields.reversed.toList();
      final container = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(_brandWithFields(reversed)),
      ]);
      addTearDown(container.dispose);

      expect(container.read(registrationFieldsProvider).map((s) => s.id), reversed);
    });

    test('a field the socle does not know is dropped, not crashed on', () {
      // An unknown id is a warning, not an error, so it reaches this provider.
      // Rendering must survive it.
      final container = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(
            _brandWithFields([...kUserRequiredRegistrationFields, 'favouriteColour'])),
      ]);
      addTearDown(container.dispose);

      expect(container.read(registrationFieldsProvider).map((s) => s.id),
          kUserRequiredRegistrationFields);
    });
  });

  group('validation mirrors the deployed constraints, so a round trip is not the first check', () {
    FieldSpec spec(String id) => kFieldSpecs[id]!;

    test('a required field refuses blank and whitespace', () {
      expect(validateField(spec('firstName'), ''), 'account.error.required');
      expect(validateField(spec('firstName'), '   '), 'account.error.required');
      expect(validateField(spec('firstName'), 'Ada'), isNull);
    });

    test('an optional field accepts blank', () {
      expect(validateField(spec('phoneNum'), ''), isNull);
    });

    test('a password shorter than eight is refused before the server sees it', () {
      // @Size(min = 8) — "Password must be longer than 7 characters".
      expect(kPasswordMinLength, 8);
      expect(validateField(spec('password'), 'Abc!12'), 'account.error.passwordShort');
      expect(validateField(spec('password'), 'Abcdefg!'), isNull);
    });

    test('the pattern wants a case pair and a symbol — and no digit', () {
      // @Pattern(^(?=.*[a-z])(?=.*[A-Z])(?=.*[^a-zA-Z0-9]).*$). A rule that
      // demanded a digit here would reject passwords the server accepts.
      expect(validateField(spec('password'), 'Abcdefg!'), isNull);
      expect(validateField(spec('password'), 'abcdefg!'), 'account.error.passwordWeak');
      expect(validateField(spec('password'), 'ABCDEFG!'), 'account.error.passwordWeak');
      expect(validateField(spec('password'), 'Abcdefgh'), 'account.error.passwordWeak');
    });

    test('an address that is not one is refused', () {
      expect(validateField(spec('email'), 'ada'), 'account.error.email');
      expect(validateField(spec('email'), 'ada@example'), 'account.error.email');
      expect(validateField(spec('email'), 'ada@example.test'), isNull);
    });
  });

  group('the request carries every field the server requires', () {
    test('all eleven @NotNull fields are present and non-null', () async {
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).register(filledDraft(), language: 'fr');

      final body = wire.last.data as Map<String, dynamic>;
      for (final field in kServerRequiredRegistrationFields) {
        expect(body.containsKey(field), isTrue, reason: 'missing "$field" — a 400 on every sign-up');
        expect(body[field], isNotNull, reason: '"$field" is @NotNull server-side');
      }
    });

    test('title is sent empty rather than null', () {
      // The live app sends null against a @NotNull field. Empty satisfies the
      // constraint under either reading; the discrepancy is a backend question,
      // not something to guess at.
      expect(kServerRequiredRegistrationFields, contains('title'));
      expect(kAppSuppliedRegistrationFields, contains('title'));
    });

    test('the date of birth serialises as the LocalDate the server parses', () async {
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).register(filledDraft(), language: 'fr');
      expect((wire.last.data as Map)['dateOfBirth'], '1815-12-10');
    });

    test('the country travels with the two keys CountryModel declares @NotNull', () async {
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).register(filledDraft(), language: 'fr');
      final country = (wire.last.data as Map)['country'] as Map;
      expect(country['id'], 75);
      expect(country['code'], 'FR');
      expect(country['language'], 'fr');
    });

    test('the interface language is sent, not inferred server-side', () async {
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).register(filledDraft(), language: 'ar');
      expect((wire.last.data as Map)['language'], 'ar');
      expect(wire.last.headers['Accept-Language'], 'fr');
    });
  });

  group('the endpoints are the deployed ones', () {
    test('activation is the PUT-shaped extended route, not stock JHipster', () async {
      // The old client called GET /api/activate?key=, which is not what the
      // deployed SubscriberResource exposes.
      final wire = FakeWire(body: <String, dynamic>{});
      await repoOn(wire).verify(email: 'a@b.test', code: '123456');
      expect(wire.last.path, '/v1/subscribers/account/activate');
      // The name always said PUT; nothing checked it, and the app sent POST.
      expect(wire.last.method, 'PUT');
      expect(wire.last.queryParameters['key'], '123456');
      expect(wire.last.queryParameters['email'], 'a@b.test');
    });

    test('sign-in reads id_token and nothing else', () async {
      final wire = FakeWire(body: <String, dynamic>{'id_token': 'abc'});
      expect(await repoOn(wire).signIn(email: 'a@b.test', password: 'x'), 'abc');
    });

    test('a 200 with no id_token is a failure, not an empty session', () async {
      // The old client stored '' here and treated it as signed in.
      final wire = FakeWire(body: <String, dynamic>{'user': <String, dynamic>{}});
      await expectLater(
        repoOn(wire).signIn(email: 'a@b.test', password: 'x'),
        throwsA(isA<AccountFailure>()),
      );
    });

    test('a public call does not carry a stale bearer', () async {
      // auth: false has to mean it. A leftover expired token on /authenticate
      // fails the very sign-in meant to replace it.
      final wire = FakeWire(body: <String, dynamic>{'id_token': 'abc'});
      await repoOn(wire, token: 'stale').signIn(email: 'a@b.test', password: 'x');
      expect(wire.last.headers.containsKey('Authorization'), isFalse);
    });

    test('an authenticated call does carry it', () async {
      final wire = FakeWire(body: <String, dynamic>{'email': 'a@b.test'});
      await repoOn(wire, token: 'live').profile();
      expect(wire.last.headers['Authorization'], 'Bearer live');
    });

    test('a malformed country row is skipped, not fatal', () async {
      final wire = FakeWire(body: <dynamic>[
        {'id': 1, 'code': 'FR', 'name': 'France'},
        {'code': 'XX', 'name': 'No id'},
        'not a country',
        {'id': 2, 'code': 'DZ', 'country': 'Algérie'},
      ]);
      final countries = await repoOn(wire).countries();
      expect(countries.map((c) => c.code), <String>['DZ', 'FR']);
    });
  });

  group('auth state transitions', () {
    ProviderContainer withRepo(FakeRepository repo) {
      final c = ProviderContainer(overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        brandConfigProvider.overrideWithValue(_brandWithFields(kUserRequiredRegistrationFields)),
        sessionStoreProvider.overrideWithValue(SessionStore(storage: SpyStorage())),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a good sign-in ends done', () async {
      final c = withRepo(FakeRepository());
      await c.read(authControllerProvider.notifier).signIn('a@b.test', 'Abcdefg!');
      expect(c.read(authControllerProvider), isA<AuthDone>());
    });

    test('a 401 during sign-in reads as bad credentials, not an expired session', () async {
      // The network layer maps 401 to SessionExpired, which is right for a
      // stale token and misleading on a login form.
      final c = withRepo(FakeRepository()..failWith = const SessionExpired());
      await c.read(authControllerProvider.notifier).signIn('a@b.test', 'nope');
      expect((c.read(authControllerProvider) as AuthFailed).messageKey,
          'account.error.badCredentials');
    });

    test('registration waits for the emailed code rather than assuming a session', () async {
      final repo = FakeRepository();
      final c = withRepo(repo);
      await c.read(authControllerProvider.notifier).register(filledDraft());
      final state = c.read(authControllerProvider);
      expect(state, isA<AuthAwaitingCode>());
      expect((state as AuthAwaitingCode).email, 'a@b.test');
      expect(repo.registered, isNotNull);
    });

    test('a duplicate account is named, not shown as a generic failure', () async {
      final c = withRepo(FakeRepository()
        ..failWith = const HttpFailure(400, serverCode: 'error.idexists'));
      await c.read(authControllerProvider.notifier).register(filledDraft());
      expect((c.read(authControllerProvider) as AuthFailed).messageKey,
          'account.error.emailTaken');
    });

    test('a wrong code is named', () async {
      final c = withRepo(FakeRepository()..failWith = const HttpFailure(400));
      await c.read(authControllerProvider.notifier).verify(email: 'a@b.test', code: '000000');
      expect((c.read(authControllerProvider) as AuthFailed).messageKey, 'account.error.badCode');
    });

    test('a failed resend does not replace the screen the user is working in', () async {
      final repo = FakeRepository()..failWith = const NetworkUnavailable('timeout');
      final c = withRepo(repo);
      await c.read(authControllerProvider.notifier).resendCode('a@b.test');
      expect(c.read(authControllerProvider), isA<AuthIdle>());
      expect(repo.resendCalls, 1);
    });

    test('the profile does not survive a change of user', () async {
      // Caught on a device, not in review: after verifying a second account the
      // Profile tab still showed the FIRST user's name and email, and no
      // GET /api/account had been sent. A profile cached across sessions is a
      // disclosure, not a stale label.
      final repo = _SwitchableRepository();
      final c = ProviderContainer(overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        brandConfigProvider.overrideWithValue(_brandWithFields(kUserRequiredRegistrationFields)),
        sessionStoreProvider.overrideWithValue(SessionStore(storage: SpyStorage())),
      ]);
      addTearDown(c.dispose);

      await c.read(sessionProvider.notifier).signIn(_jwt('ada@example.test'));
      expect((await c.read(profileProvider.future)).email, 'ada@example.test');

      repo.email = 'grace@example.test';
      await c.read(sessionProvider.notifier).signIn(_jwt('grace@example.test'));
      expect((await c.read(profileProvider.future)).email, 'grace@example.test');
      expect(repo.fetches, 2, reason: 'the second user was served from the first user cache');
    });

    test('an offline failure surfaces the network key, not a server string', () async {
      final c = withRepo(FakeRepository()..failWith = const NetworkUnavailable('timeout'));
      await c.read(authControllerProvider.notifier).signIn('a@b.test', 'Abcdefg!');
      expect((c.read(authControllerProvider) as AuthFailed).messageKey,
          'error.network_unavailable');
    });
  });
}

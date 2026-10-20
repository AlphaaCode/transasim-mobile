/// The sign-up form, as a person meets it.
///
/// It asks for no phone number, on purpose, and the request still carries
/// `"phoneNum": ""` (the backend answers 500 to `null` or an absent key). So
/// the interesting assertions are two: that the form really has no phone field,
/// and that what it sends — through the REAL repository — has the key anyway.
/// The rest is what a weak password and each server answer look like on screen.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/result/result.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';
import 'package:transasim_mobile/modules/account/presentation/auth_screens.dart';

import '../core/brand_config_test.dart' show validJson;
import '../modules/account_test.dart' show FakeRepository, FakeWire, repoOn;

/// A repository that counts how often it was asked to register anyone.
class _Counting extends FakeRepository {
  int registerCalls = 0;

  @override
  Future<void> register(RegistrationDraft draft, {required String language}) {
    registerCalls++;
    return super.register(draft, language: language);
  }
}

class _English extends LanguageController {
  @override
  String build() => 'en';
}

/// The shipped brands' order, minus the country picker (which needs a network
/// to fill and says nothing about what is under test).
BrandConfig _brand() {
  final json = validJson()
    ..['locales'] = ['en']
    ..['defaultLocale'] = 'en';
  (json['mobile'] as Map)['registration'] = <String, dynamic>{
    'fields': ['firstName', 'lastName', 'email', 'password'],
  };
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

// The order the text fields appear on the page.
const _firstName = 0, _lastName = 1, _email = 2, _password = 3, _confirm = 4;

Future<void> _pump(WidgetTester tester, AccountRepository repo) async {
  // Tall enough that every field is built: the form is a lazy list.
  tester.view.physicalSize = const Size(412, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final brand = _brand();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const RegisterScreen()),
    GoRoute(
      path: '/verify',
      name: 'verify',
      builder: (_, _) => const Scaffold(body: Text('VERIFY')),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(brand),
      languageProvider.overrideWith(_English.new),
      accountRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(theme: buildTheme(brand), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, int field, String value) async {
  await tester.enterText(find.byType(TextField).at(field), value);
  await tester.pump();
}

Future<void> _fill(WidgetTester tester, {String password = 'Abcdefg!'}) async {
  await _type(tester, _firstName, 'Ada');
  await _type(tester, _lastName, 'Lovelace');
  await _type(tester, _email, 'ada@example.test');
  await _type(tester, _password, password);
  await _type(tester, _confirm, password);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Create account'));
  await tester.pumpAndSettle();
}

void main() {
  group('the form asks for no phone number', () {
    testWidgets('there is no phone field, and five boxes in all', (tester) async {
      await _pump(tester, _Counting());

      expect(find.text('Phone number'), findsNothing);
      expect(find.byIcon(Icons.phone_outlined), findsNothing);
      // first name, last name, e-mail, password, confirm password
      expect(find.byType(TextField), findsNWidgets(5));
    });

    testWidgets('and a sign-up still puts "phoneNum": "" on the wire', (tester) async {
      // The REAL repository over an in-memory wire: what leaves the app, not
      // what a fake was handed.
      final wire = FakeWire(body: <String, dynamic>{});
      await _pump(tester, repoOn(wire));

      await _fill(tester);
      await _submit(tester);

      expect(wire.sent, hasLength(1), reason: 'one sign-up, one request');
      expect(wire.last.path, '/v1/subscribers/register');
      final body = jsonDecode(jsonEncode(wire.last.data)) as Map<String, dynamic>;
      expect(body.containsKey('phoneNum'), isTrue, reason: 'an absent key is a 500');
      expect(body['phoneNum'], isNotNull, reason: 'null is a 500');
      expect(body['phoneNum'], '');
      expect(find.text('VERIFY'), findsOneWidget, reason: 'the activation code is next');
    });
  });

  group('a password the server would refuse never leaves the app', () {
    testWidgets('no capital, no symbol: nothing is sent, and it says what to add',
        (tester) async {
      final repo = _Counting();
      await _pump(tester, repo);

      await _fill(tester, password: 'abcdefgh');
      await _submit(tester);

      expect(repo.registerCalls, 0);
      expect(find.text('Add an uppercase letter, a lowercase letter and a symbol'),
          findsOneWidget);
    });

    testWidgets('shorter than eight: nothing is sent, and it says how long', (tester) async {
      final repo = _Counting();
      await _pump(tester, repo);

      await _fill(tester, password: 'Abc!1');
      await _submit(tester);

      expect(repo.registerCalls, 0);
      expect(find.text('At least 8 characters'), findsOneWidget);
    });

    testWidgets('a good one goes through once', (tester) async {
      final repo = _Counting();
      await _pump(tester, repo);

      await _fill(tester);
      await _submit(tester);

      expect(repo.registerCalls, 1);
      expect(find.text('VERIFY'), findsOneWidget);
    });
  });

  group('what the server says is what the person reads', () {
    const alreadyThere = 'This e-mail already has an account. Log in or reset your password.';

    for (final (code, sentence) in const [
      ('error.userexists', alreadyThere),
      ('error.emailexists', alreadyThere),
      ('error.idexists', alreadyThere),
      ('error.emaildomainnotallowed', 'This e-mail domain is not accepted'),
    ]) {
      testWidgets(code, (tester) async {
        final repo = _Counting()..failWith = HttpFailure(400, serverCode: code);
        await _pump(tester, repo);

        await _fill(tester);
        await _submit(tester);

        expect(repo.registerCalls, 1);
        expect(find.text(sentence), findsOneWidget);
        expect(find.text('Something went wrong. Please try again.'), findsNothing,
            reason: 'a named refusal must not read as a generic failure');
      });
    }

    testWidgets("a validation failure puts the server's wording under its field",
        (tester) async {
      final repo = _Counting()
        ..failWith = const HttpFailure(
          400,
          serverCode: 'error.validation',
          fieldErrors: {'email': 'This address is not accepted here'},
        );
      await _pump(tester, repo);

      await _fill(tester);
      await _submit(tester);

      expect(find.text('This address is not accepted here'), findsOneWidget);
      expect(find.text('Please check the highlighted fields'), findsOneWidget);

      // Under the e-mail field, not under another one.
      final emailBox = find.ancestor(
        of: find.byType(TextField).at(_email),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(
          of: emailBox.first,
          matching: find.text('This address is not accepted here'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a 400 nothing is known about stays the generic line', (tester) async {
      final repo = _Counting()..failWith = const HttpFailure(400, serverCode: 'error.new');
      await _pump(tester, repo);

      await _fill(tester);
      await _submit(tester);

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    });
  });
}

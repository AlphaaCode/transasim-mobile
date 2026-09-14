import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/result/result.dart';
import 'package:transasim_mobile/modules/account/data/account_repository_impl.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';
import 'package:transasim_mobile/modules/account/presentation/auth_screens.dart';

import '../core/session_test.dart' show SpyStorage, jwt;
import 'real_fonts.dart';

/// Reported: Forgot Password -> email -> Send left the user on the Store, as if
/// signed in. These replay that flow through the real screens and the real
/// router, and watch the two things that matter: where navigation went, and
/// whether anything was written as a session.

class _FakeAccount implements AccountRepository {
  final List<String> resetRequests = [];
  String? verifyToken;
  String? signInToken;
  ({String code, String newPassword})? finished;
  Object? finishError;

  @override
  Future<void> finishPasswordReset({required String code, required String newPassword}) async {
    if (finishError != null) throw finishError!;
    finished = (code: code, newPassword: newPassword);
  }

  @override
  Future<String> signIn({required String email, required String password}) async => signInToken!;

  @override
  Future<void> requestPasswordReset(String email) async => resetRequests.add(email);

  @override
  Future<String?> verify({required String email, required String code}) async => verifyToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

BrandConfig _sabily() {
  final json =
      jsonDecode(File('brands/sabily/brand.json').readAsStringSync()) as Map<String, dynamic>;
  return BrandConfig.parse(json, expectedSlug: 'sabily').config as BrandConfig;
}

Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester tester, {
  required SpyStorage storage,
  required _FakeAccount account,
  required String initial,
}) async {
  final brand = _sabily();
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/sign-in', name: 'signIn', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify',
        name: 'verify',
        builder: (_, s) => VerifyScreen(email: s.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: '/reset-password',
        name: 'resetPassword',
        builder: (_, s) => ResetPasswordScreen(email: s.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(path: '/store', name: 'store', builder: (_, _) => const Text('STORE')),
      GoRoute(path: '/register', name: 'register', builder: (_, _) => const Text('REGISTER')),
    ],
  );
  final container = ProviderContainer(overrides: [
    brandConfigProvider.overrideWithValue(brand),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    sessionStoreProvider.overrideWithValue(SessionStore(storage: storage)),
    accountRepositoryProvider.overrideWithValue(account),
  ]);
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: buildTheme(brand), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (router, container);
}

/// The app always provides storage (bootstrap overrides it); so do these.
late SharedPreferences _prefs;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });
  // Real glyph metrics, so a label row that fits on a phone fits here too.
  setUpAll(loadRealFonts);

  testWidgets('sending a password reset does not land the user in the app', (tester) async {
    final storage = SpyStorage();
    final account = _FakeAccount();
    final (router, container) =
        await _pump(tester, storage: storage, account: account, initial: '/sign-in');

    // Sign In stays mounted underneath, exactly as on the device.
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ada@example.test');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();

    expect(account.resetRequests, ['ada@example.test']);
    // Nothing resembling a session came into being...
    expect(storage.writes, isEmpty);
    expect(container.read(isSignedInProvider), isFalse);
    // ...so landing on the Store would be navigation alone.
    expect(find.text('STORE'), findsNothing, reason: 'reset success navigated as if signed in');
    // On the code step, which says a code was sent and asks for it.
    expect(find.text('Code reçu par e-mail'), findsOneWidget);
  });

  testWidgets('activation that issues no token sends the user to sign in, not into the app',
      (tester) async {
    // The live backend answers activation with a plain-text line and no
    // id_token, so this is the path every real activation takes.
    final storage = SpyStorage();
    final account = _FakeAccount()..verifyToken = null;
    final (router, container) = await _pump(
      tester,
      storage: storage,
      account: account,
      initial: '/verify?email=ada@example.test',
    );

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();

    expect(storage.writes, isEmpty);
    expect(container.read(isSignedInProvider), isFalse);
    expect(find.text('STORE'), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/sign-in');
  });

  testWidgets('a real sign-in still enters the app, because a session now exists', (tester) async {
    final storage = SpyStorage();
    final account = _FakeAccount()
      ..signInToken = jwt(exp: DateTime.now().add(const Duration(hours: 1)));
    final (_, container) =
        await _pump(tester, storage: storage, account: account, initial: '/sign-in');

    await tester.enterText(find.byType(TextField).at(0), 'ada@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'Abcdefg!');
    await tester.tap(find.text('Se connecter').last);
    await tester.pumpAndSettle();

    expect(storage.writes, isNotEmpty);
    expect(container.read(isSignedInProvider), isTrue);
    expect(find.text('STORE'), findsOneWidget);
  });

  testWidgets('code + new password resets it and returns to Sign In, signed out', (tester) async {
    final storage = SpyStorage();
    final account = _FakeAccount();
    final (_, container) =
        await _pump(tester, storage: storage, account: account, initial: '/sign-in');

    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ada@example.test');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();

    // The client-side rule catches a weak password before any request.
    await tester.enterText(find.byType(TextField).at(0), 'A1B2C3');
    await tester.enterText(find.byType(TextField).at(1), 'weak');
    await tester.tap(find.text('Réinitialiser mon mot de passe'));
    await tester.pumpAndSettle();
    expect(account.finished, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'Newpass1!');
    await tester.tap(find.text('Réinitialiser mon mot de passe'));
    await tester.pumpAndSettle();

    expect(account.finished, (code: 'A1B2C3', newPassword: 'Newpass1!'));
    expect(find.text('Bon retour'), findsOneWidget, reason: 'back on Sign In');
    expect(find.text('Votre mot de passe a été modifié. Connectez-vous avec le nouveau.'), findsOneWidget);
    expect(storage.writes, isEmpty);
    expect(container.read(isSignedInProvider), isFalse);
  });

  testWidgets('a wrong code says so and stays on the code step', (tester) async {
    final account = _FakeAccount()
      ..finishError = const AccountFailure(
          HttpFailure(500, serverMessage: 'No user was found for this reset key'));
    await _pump(tester,
        storage: SpyStorage(), account: account, initial: '/reset-password?email=ada@example.test');

    await tester.enterText(find.byType(TextField).at(0), 'ZZZ999');
    await tester.enterText(find.byType(TextField).at(1), 'Newpass1!');
    await tester.tap(find.text('Réinitialiser mon mot de passe'));
    await tester.pumpAndSettle();

    expect(find.text("Ce code n'est pas valide"), findsOneWidget);
    expect(find.text('Code reçu par e-mail'), findsOneWidget);
  });
}

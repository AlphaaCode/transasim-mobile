/// Apple 5.1.1(v): an app with accounts must let one be deleted from inside
/// the app.
///
/// eSimple 2.0.0 was rejected for having no such path. There is no delete
/// endpoint yet, so the app opens the brand's web form — which the guideline
/// allows, as long as the journey BEGINS in the app. What these hold down is
/// that it does begin there, that it never begins for a brand with no form,
/// and that nothing about the user travels in the URL.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/l10n.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';
import 'package:transasim_mobile/modules/account/presentation/profile_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what was launched and answers a fixed verdict.
class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  FakeLauncher({this.opens = true, this.throws});

  final bool opens;

  /// `launchUrl` THROWS when no activity can handle the link, rather than
  /// returning false. Both are the same outcome to a user, so both are run.
  final Object? throws;

  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    final boom = throws;
    if (boom != null) throw boom;
    return opens;
  }
}

BrandConfig brand(String slug) {
  final json = jsonDecode(File('brands/$slug/brand.json').readAsStringSync());
  final r = BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: slug);
  if (r.errors.isNotEmpty) throw StateError(r.describe(slug));
  return r.config as BrandConfig;
}

final _sabily = brand('sabily');
final _acorn = brand('acorn');

Future<void> pumpProfile(
  WidgetTester tester, {
  required BrandConfig config,
  required bool signedIn,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // Tall enough that the whole page is laid out. The screen is a ListView and
  // the row sits below the fold on a normal phone, so on the default 800x600
  // surface "not found" would mean "not scrolled to" — which would make the
  // absence assertions prove nothing at all.
  tester.view.physicalSize = const Size(412, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(config),
      sharedPreferencesProvider.overrideWithValue(prefs),
      allModulesProvider.overrideWithValue(const []),
      isSignedInProvider.overrideWithValue(signedIn),
      languageProvider.overrideWith(() => _FixedLanguage(config.defaultLocale)),
      profileProvider.overrideWith((ref) async =>
          const Profile(id: 1, email: 'a@b.test', firstName: 'Test', lastName: 'User')),
    ],
    child: MaterialApp(
      theme: buildTheme(config),
      home: const ProfileScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UrlLauncherPlatform original;
  setUp(() => original = UrlLauncherPlatform.instance);
  tearDown(() => UrlLauncherPlatform.instance = original);

  String rowLabel(BrandConfig b) =>
      L10n(brand: b, language: b.defaultLocale).t('account.delete.row');

  group('the brand schema', () {
    test('sabily and esimple carry an https deletion form', () {
      for (final slug in ['sabily', 'esimple']) {
        final url = brand(slug).legal.accountDeletionUrl;
        expect(url, isNotNull, reason: slug);
        expect(Uri.parse(url!).scheme, 'https', reason: slug);
      }
    });

    test('acorn has none, and that is not an error', () {
      expect(_acorn.legal.accountDeletionUrl, isNull);
      final json = jsonDecode(File('brands/acorn/brand.json').readAsStringSync());
      final parsed = BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'acorn');
      expect(parsed.errors, isEmpty, reason: 'absence is a warning, never a hard failure');
    });

    test('a non-https form is rejected rather than shipped', () {
      final json =
          jsonDecode(File('brands/sabily/brand.json').readAsStringSync()) as Map<String, dynamic>;
      (json['legal'] as Map<String, dynamic>)['accountDeletionUrl'] = 'http://sabily.fr/delete';
      final parsed = BrandConfig.parse(json, expectedSlug: 'sabily');
      expect(parsed.errors.join(' '), contains('legal.accountDeletionUrl'));
    });
  });

  group('the row', () {
    testWidgets('is there when signed in and a form is configured', (tester) async {
      await pumpProfile(tester, config: _sabily, signedIn: true);
      expect(find.text(rowLabel(_sabily)), findsOneWidget);
    });

    testWidgets('is absent when signed out', (tester) async {
      await pumpProfile(tester, config: _sabily, signedIn: false);
      expect(find.text(rowLabel(_sabily)), findsNothing);
    });

    testWidgets('is absent for a brand with no form, even signed in', (tester) async {
      // Acorn has no URL yet. A row here would be a button that goes nowhere,
      // which is its own 5.1.1(v) rejection.
      await pumpProfile(tester, config: _acorn, signedIn: true);
      expect(find.text(rowLabel(_acorn)), findsNothing);
    });
  });

  group('the confirmation', () {
    testWidgets('names the brand and states the consequences before anything opens',
        (tester) async {
      final launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      final l10n = L10n(brand: _sabily, language: _sabily.defaultLocale);

      await pumpProfile(tester, config: _sabily, signedIn: true);
      await tester.tap(find.text(rowLabel(_sabily)));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('account.delete.title')), findsOneWidget);
      expect(find.text(l10n.t('account.delete.body')), findsOneWidget);
      expect(find.textContaining(_sabily.name), findsWidgets,
          reason: 'the dialog has to say WHICH account is being deleted');
      expect(launcher.launched, isEmpty, reason: 'nothing opens before Continue');
    });

    testWidgets('Cancel opens nothing', (tester) async {
      final launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      final l10n = L10n(brand: _sabily, language: _sabily.defaultLocale);

      await pumpProfile(tester, config: _sabily, signedIn: true);
      await tester.tap(find.text(rowLabel(_sabily)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.t('common.cancel')));
      await tester.pumpAndSettle();

      expect(launcher.launched, isEmpty);
      expect(find.text(l10n.t('account.delete.title')), findsNothing);
    });

    testWidgets('Continue opens the brand URL externally, carrying nothing about the user',
        (tester) async {
      final launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      final l10n = L10n(brand: _sabily, language: _sabily.defaultLocale);

      await pumpProfile(tester, config: _sabily, signedIn: true);
      await tester.tap(find.text(rowLabel(_sabily)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.t('common.continue')));
      await tester.pumpAndSettle();

      expect(launcher.launched.single, _sabily.legal.accountDeletionUrl);

      // No email, no token, no id — not in the query string, not anywhere.
      final sent = launcher.launched.single;
      expect(sent, isNot(contains('a@b.test')));
      expect(sent, isNot(contains('?')), reason: 'no query string at all is the simplest proof');
      for (final leak in ['email', 'token', 'userId', 'user_id', 'bearer']) {
        expect(sent.toLowerCase(), isNot(contains(leak.toLowerCase())), reason: leak);
      }
    });
  });

  group('when the browser cannot be opened', () {
    for (final (name, launcher) in <(String, FakeLauncher)>[
      ('launchUrl answers false', FakeLauncher(opens: false)),
      ('launchUrl throws', FakeLauncher(throws: Exception('no activity'))),
    ]) {
      testWidgets('$name: the address is shown as copyable text', (tester) async {
        UrlLauncherPlatform.instance = launcher;
        final l10n = L10n(brand: _sabily, language: _sabily.defaultLocale);

        await pumpProfile(tester, config: _sabily, signedIn: true);
        await tester.tap(find.text(rowLabel(_sabily)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.t('common.continue')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.t('account.delete.failed')), findsOneWidget);
        final shown = find.byWidgetPredicate((w) =>
            w is SelectableText && w.data == _sabily.legal.accountDeletionUrl);
        expect(shown, findsOneWidget,
            reason: 'a user with no browser handler must still be able to copy it out');
      });
    }
  });

  group('every locale can render it', () {
    test('all 7 locales carry the deletion strings', () {
      for (final code in _sabily.locales) {
        final l10n = L10n(brand: _sabily, language: code);
        for (final key in ['account.delete.row', 'account.delete.title',
                           'account.delete.body', 'account.delete.failed',
                           'profile.account']) {
          final v = l10n.t(key);
          expect(v, isNot(key), reason: '$code is missing $key');
          expect(v.trim(), isNotEmpty, reason: '$code has $key empty');
        }
      }
    });

    test('the body names the 30 days and the eSIMs in every locale', () {
      for (final code in _sabily.locales) {
        final body = L10n(brand: _sabily, language: code).t('account.delete.body');
        expect(body, contains('30'), reason: '$code must state the 30-day window');
        expect(body.toLowerCase(), contains('esim'), reason: '$code must warn about the plans');
      }
    });
  });
}

/// The brand's default locale, pinned. Empty preferences make the controller
/// fall back to the DEVICE locale, which is English under test — so without
/// this, Sabily's screen renders in English and every label assertion here
/// would be checking a language the brand does not open in.
class _FixedLanguage extends LanguageController {
  _FixedLanguage(this._value);
  final String _value;

  @override
  String build() => _value;
}

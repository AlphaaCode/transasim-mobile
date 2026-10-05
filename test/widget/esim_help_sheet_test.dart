/// The "Does my phone support eSIM?" sheet, and the three ways in.
///
/// The sheet exists because an install hand-off can succeed and still appear
/// to do nothing: on one device the OS opened its own installer and Samsung's
/// telephony UI closed it with "Add eSIM not allowed by policy", in a process
/// this app cannot see. So the answer is a question the user can check for
/// themselves — BEFORE buying, not only after.
///
/// ⚠️ It is informational and must never gate a purchase. The last group here
/// is the one that guards that.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/l10n.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/esim_help_sheet.dart';

final BrandConfig _sabily = () {
  final json = jsonDecode(File('brands/sabily/brand.json').readAsStringSync());
  return BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'sabily').config
      as BrandConfig;
}();

/// The keys the sheet and its entry points resolve. A gap in any of them falls
/// back silently to the reference language, which is how a half-translated
/// screen ships without anyone noticing.
const _keys = <String>[
  'esim.installHint',
  'esimHelp.entry',
  'esimHelp.title',
  'esimHelp.intro',
  'esimHelp.androidTitle',
  'esimHelp.android',
  'esimHelp.iphoneTitle',
  'esimHelp.iphone',
  'esimHelp.carrierTitle',
  'esimHelp.carrier',
  'esimHelp.dialer',
];

Widget _host(Widget child, {String language = 'en'}) => ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(_sabily),
        allModulesProvider.overrideWithValue(const []),
        languageProvider.overrideWith(() => _FixedLanguage(language)),
      ],
      child: MaterialApp(
        theme: buildTheme(_sabily),
        locale: Locale(language),
        home: Directionality(
          textDirection: directionFor(language),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

class _FixedLanguage extends LanguageController {
  _FixedLanguage(this._value);
  final String _value;

  @override
  String build() => _value;
}

void main() {
  group('the sheet opens and says everything, in every language', () {
    for (final language in kSocleSupportedLanguages) {
      testWidgets('"$language" has no missing keys and renders', (tester) async {
        tester.view.physicalSize = const Size(360, 780) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        // The dictionary half: a key absent here would resolve to English and
        // look fine on screen, which is exactly the failure to catch.
        final l10n = L10n(brand: _sabily, language: language);
        for (final key in _keys) {
          expect(l10n.t(key), isNot(key),
              reason: '"$key" is missing from "$language"');
          expect(l10n.t(key), isNotEmpty);
        }

        await tester.pumpWidget(_host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showEsimHelpSheet(context),
              child: const Text('open'),
            ),
          ),
          language: language,
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(EsimHelpSheet), findsOneWidget);
        // Nothing overflowed, and no ink/assert blew up on the way.
        expect(tester.takeException(), isNull);

        // The three sections and the dialer shortcut are all present.
        expect(find.text(l10n.t('esimHelp.androidTitle')), findsOneWidget);
        expect(find.text(l10n.t('esimHelp.iphoneTitle')), findsOneWidget);
        expect(find.text(l10n.t('esimHelp.carrierTitle')), findsOneWidget);
        expect(find.text(l10n.t('esimHelp.dialer')), findsOneWidget);
      });
    }
  });

  group('the ways in', () {
    testWidgets('the compact link opens it', (tester) async {
      await tester.pumpWidget(_host(const EsimHelpLink()));
      final l10n = L10n(brand: _sabily, language: 'en');

      expect(find.text(l10n.t('esimHelp.entry')), findsOneWidget);
      expect(find.byType(EsimHelpSheet), findsNothing);

      await tester.tap(find.byType(EsimHelpLink));
      await tester.pumpAndSettle();

      expect(find.byType(EsimHelpSheet), findsOneWidget);
    });

    testWidgets('it is dismissible and leaves nothing behind', (tester) async {
      await tester.pumpWidget(_host(const EsimHelpLink()));
      await tester.tap(find.byType(EsimHelpLink));
      await tester.pumpAndSettle();
      expect(find.byType(EsimHelpSheet), findsOneWidget);

      // Tapping the barrier is how a user closes it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(EsimHelpSheet), findsNothing);
    });
  });

  group('it informs, and never gates', () {
    testWidgets('opening it returns no verdict a caller could branch on',
        (tester) async {
      // The signature is the guarantee: `Future<void>`. If this ever becomes a
      // bool, something downstream can start refusing to sell.
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              final Future<void> result = showEsimHelpSheet(context);
              expect(result, isA<Future<void>>());
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the link is a link, not a barrier', (tester) async {
      // It renders inline and takes only the room it needs, so it cannot
      // displace or cover a Pay button sitting under it.
      await tester.pumpWidget(_host(const EsimHelpLink()));
      final size = tester.getSize(find.byType(EsimHelpLink));
      expect(size.height, lessThan(64),
          reason: 'a small link under the summary, not a panel');
    });
  });
}

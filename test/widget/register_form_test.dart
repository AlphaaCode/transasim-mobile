import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';
import 'package:transasim_mobile/modules/account/presentation/auth_screens.dart';

import '../core/brand_config_test.dart' show validJson;

/// The registration form is the densest screen in the app: ten labelled fields
/// in fixed-height boxes, in seven languages, two directions. It is where a
/// label overflows first — `Postleitzahl`, `Datum rojstva`, `البريد الإلكتروني`
/// are all materially longer than `Ville`.

BrandConfig brandWith(List<String> locales, {List<String>? fields}) {
  final json = validJson()
    ..['locales'] = locales
    ..['defaultLocale'] = locales.first;
  (json['mobile'] as Map)['registration'] = <String, dynamic>{
    'fields': fields ?? [...kUserRequiredRegistrationFields, 'phoneNum'],
  };
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

class _FixedLanguage extends LanguageController {
  final String value;
  _FixedLanguage(this.value);
  @override
  String build() => value;
}

Widget harness(BrandConfig brand, String language) => ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(brand),
        languageProvider.overrideWith(() => _FixedLanguage(language)),
        // The picker would otherwise reach for the network on first build.
        countriesProvider.overrideWith((ref) async => const [
              CountryRef(id: 75, code: 'FR', name: 'France', language: 'fr'),
              CountryRef(id: 1, code: 'DZ', name: 'Algérie', language: 'ar'),
            ]),
      ],
      child: MaterialApp(
        theme: buildTheme(brand),
        locale: Locale(language),
        home: Directionality(
          textDirection: directionFor(language),
          child: const RegisterScreen(),
        ),
      ),
    );

void main() {
  testWidgets('every language renders the whole form without overflow', (tester) async {
    final brand = brandWith(kSocleSupportedLanguages);
    for (final lang in kSocleSupportedLanguages) {
      await tester.pumpWidget(harness(brand, lang));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'language "$lang" threw while rendering');
    }
  });

  testWidgets('Arabic lays the form out right-to-left', (tester) async {
    await tester.pumpWidget(harness(brandWith(const ['ar', 'fr']), 'ar'));
    await tester.pump();

    expect(Directionality.of(tester.element(find.byType(RegisterScreen))), TextDirection.rtl);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
  });

}

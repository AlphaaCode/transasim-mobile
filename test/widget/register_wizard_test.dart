import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/app_button.dart';
import 'package:transasim_mobile/core/ui/app_card.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';
import 'package:transasim_mobile/modules/account/presentation/auth_screens.dart';

import '../core/brand_config_test.dart' show validJson;

/// The wizard drives off `registration.steps`, so these tests configure steps
/// the way a brand would and check what the user actually sees and can do.

const List<Map<String, Object>> _sabilyShapedSteps = [
  {'title': 'account.step.identity', 'fields': ['firstName', 'lastName', 'email', 'phoneNum']},
  {'title': 'account.step.security', 'fields': ['password']},
  {
    'title': 'account.step.details',
    'fields': ['dateOfBirth', 'address', 'zipCode', 'city', 'country'],
  },
];

BrandConfig brandWith({List<Map<String, Object>>? steps}) {
  final json = validJson()
    ..['locales'] = ['en']
    ..['defaultLocale'] = 'en';
  (json['mobile'] as Map)['registration'] = <String, dynamic>{
    'fields': [
      'firstName', 'lastName', 'email', 'phoneNum', 'password',
      'dateOfBirth', 'address', 'zipCode', 'city', 'country',
    ],
    'steps': ?steps,
  };
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

class _FixedLanguage extends LanguageController {
  @override
  String build() => 'en';
}

Widget harness(BrandConfig brand) => ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(brand),
        languageProvider.overrideWith(_FixedLanguage.new),
        countriesProvider.overrideWith((ref) async => const [
              CountryRef(id: 75, code: 'FR', name: 'France', language: 'fr'),
            ]),
      ],
      child: MaterialApp(
        theme: buildTheme(brand),
        home: const Directionality(
          textDirection: TextDirection.ltr,
          child: RegisterScreen(),
        ),
      ),
    );

Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  await tester.enterText(
    find.descendant(of: field.first, matching: find.byType(TextField)).first,
    value,
  );
  await tester.pump();
}


/// Read the widget, not the pixels: the label is the assertion, and where it
/// happens to sit on screen is not.
String primaryActionLabel(WidgetTester tester) =>
    tester.widgetList<AppButton>(find.byType(AppButton)).last.label;

void main() {
  // A tall surface, because the list is LAZY: on a phone-height viewport the
  // submit button below ten fields is never built, and a finder cannot see
  // what does not exist. That laziness is the point — it is just inconvenient
  // to assert against.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 4400);
    view.devicePixelRatio = 3;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });
  group('a brand with steps gets a wizard', () {
    testWidgets('step one shows only its own fields', (tester) async {
      await tester.pumpWidget(harness(brandWith(steps: _sabilyShapedSteps)));
      await tester.pump();

      // Figma 52:369 puts exactly these four on step one.
      for (final label in ['First name', 'Last name', 'Email']) {
        expect(find.text(label), findsOneWidget, reason: '$label belongs on step one');
      }
      // The optional one carries its note in the same span, so it is rich text.
      expect(find.textContaining('Phone number', findRichText: true), findsWidgets,
          reason: 'phoneNum belongs on step one');
      // And none of the later steps' fields.
      for (final label in ['Password', 'City', 'Country', 'Date of birth']) {
        expect(find.text(label), findsNothing, reason: '$label is not on step one');
      }
    });

    testWidgets('the button names the step it leads to, as the design does', (tester) async {
      // "Continue to Security" is Figma's own copy. It is generated from the
      // next step's title so it follows the config rather than being written
      // into the screen.
      await tester.pumpWidget(harness(brandWith(steps: _sabilyShapedSteps)));
      await tester.pump();
      expect(find.text('Continue to Security'), findsOneWidget);
    });

    testWidgets('Continue validates THIS step only, and refuses to advance', (tester) async {
      await tester.pumpWidget(harness(brandWith(steps: _sabilyShapedSteps)));
      await tester.pump();

      await tester.tap(find.byType(AppButton));
      await tester.pump();

      // Still on step one, and told which fields are wrong.
      expect(find.text('Continue to Security'), findsOneWidget);
      expect(find.text('This field is required'), findsWidgets);

      // Crucially NOT a wall of errors for the seven fields on later steps.
      expect(find.text('Password'), findsNothing);
    });

    testWidgets('a filled step advances, and the indicator follows', (tester) async {
      await tester.pumpWidget(harness(brandWith(steps: _sabilyShapedSteps)));
      await tester.pump();

      expect(find.byType(AppStepDots), findsOneWidget);

      await fill(tester, 'First name', 'Ada');
      await fill(tester, 'Last name', 'Lovelace');
      await fill(tester, 'Email', 'ada@example.test');
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    testWidgets('the optional field does not block the step', (tester) async {
      // phoneNum is the one field the server lets through empty, and leaving it
      // blank must not trap the user on step one.
      await tester.pumpWidget(harness(brandWith(steps: _sabilyShapedSteps)));
      await tester.pump();

      await fill(tester, 'First name', 'Ada');
      await fill(tester, 'Last name', 'Lovelace');
      await fill(tester, 'Email', 'ada@example.test');
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(find.text('Security'), findsOneWidget);
    });

    testWidgets('back walks the wizard rather than leaving it', (tester) async {
      await tester.pumpWidget(harness(brandWith(steps: _sabilyShapedSteps)));
      await tester.pump();

      await fill(tester, 'First name', 'Ada');
      await fill(tester, 'Last name', 'Lovelace');
      await fill(tester, 'Email', 'ada@example.test');
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      expect(find.text('Security'), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      // Back on step one, with what was typed still there — losing a filled
      // form to a reflex tap is the failure this guards.
      expect(find.text('Continue to Security'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('the last step submits instead of continuing', (tester) async {
      await tester.pumpWidget(harness(brandWith(steps: [
        {'title': 'account.step.identity', 'fields': ['firstName', 'lastName', 'email', 'phoneNum']},
        {
          'title': 'account.step.details',
          'fields': ['password', 'dateOfBirth', 'address', 'zipCode', 'city', 'country'],
        },
      ])));
      await tester.pump();

      await fill(tester, 'First name', 'Ada');
      await fill(tester, 'Last name', 'Lovelace');
      await fill(tester, 'Email', 'ada@example.test');
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(primaryActionLabel(tester), 'Create account');
      expect(find.textContaining('Continue to'), findsNothing);
    });
  });

  group('a brand without steps keeps the single form', () {
    testWidgets('every field on one page, and no indicator', (tester) async {
      await tester.pumpWidget(harness(brandWith()));
      await tester.pump();

      expect(find.byType(AppStepDots), findsNothing);
      expect(primaryActionLabel(tester), 'Create account');
      // The fields are lazily laid out, so check a couple from each end.
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });
  });
}

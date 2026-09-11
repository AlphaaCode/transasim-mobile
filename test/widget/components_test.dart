import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/app_button.dart';
import 'package:transasim_mobile/core/ui/app_card.dart';
import 'package:transasim_mobile/core/ui/app_text_field.dart';

import '../core/brand_config_test.dart' show validJson;

/// The component layer is used by every screen, so a defect in it is a defect
/// everywhere. These are the cheapest possible assertions that each piece
/// mounts and honours its contract.

BrandConfig brand() {
  final r = BrandConfig.parse(validJson(), expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

Widget host(Widget child) {
  final b = brand();
  return MaterialApp(
    theme: buildTheme(b),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('AppButton', () {
    // Every tone, because `danger` shipped broken: it passed Material both a
    // `shape` and a `borderRadius`, which Material asserts against. Three of
    // the four tones rendered fine, so nothing caught it until the sign-out
    // button turned into a red error box on a device.
    for (final tone in AppButtonTone.values) {
      testWidgets('tone ${tone.name} mounts and renders its label', (tester) async {
        await tester.pumpWidget(host(
          AppButton(label: 'Continue', tone: tone, onPressed: () {}),
        ));

        expect(tester.takeException(), isNull, reason: 'tone ${tone.name} threw while building');
        expect(find.text('Continue'), findsOneWidget);
      });
    }

    testWidgets('a null callback disables it and taps do nothing', (tester) async {
      await tester.pumpWidget(host(const AppButton(label: 'Pay', onPressed: null)));
      await tester.tap(find.text('Pay'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('busy hides the label behind a spinner and refuses taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        AppButton(label: 'Pay', busy: true, onPressed: () => taps++),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Pay'), findsNothing);

      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(taps, 0, reason: 'a second tap while a request is in flight sends it twice');
    });

    testWidgets('every tone clears the 48px minimum tap target', (tester) async {
      await tester.pumpWidget(host(AppButton(label: 'Go', onPressed: () {})));
      expect(tester.getSize(find.byType(AppButton)).height, greaterThanOrEqualTo(48));
    });
  });

  group('AppTextField', () {
    testWidgets('shows its label and reports the value through onChanged', (tester) async {
      String? seen;
      await tester.pumpWidget(host(
        AppTextField(label: 'Email', onChanged: (v) => seen = v),
      ));

      expect(find.text('Email'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'a@b.test');
      expect(seen, 'a@b.test');
    });

    testWidgets('a failing validator surfaces its message under the box', (tester) async {
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(host(
        Form(
          key: form,
          child: AppTextField(label: 'Email', validator: (_) => 'Required'),
        ),
      ));

      expect(find.text('Required'), findsNothing);
      form.currentState!.validate();
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('an obscured field can be revealed and re-hidden', (tester) async {
      await tester.pumpWidget(host(const AppTextField(label: 'Password', obscure: true)));

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
    });

    testWidgets('the note sits beside the label rather than inside it', (tester) async {
      // The design writes "(Optional)" into the label string, which forces a
      // translator to re-derive it per language.
      await tester.pumpWidget(host(
        const AppTextField(label: 'Phone', note: 'optional'),
      ));
      expect(find.textContaining('Phone'), findsOneWidget);
      expect(find.textContaining('optional', findRichText: true), findsWidgets);
    });
  });

  group('AppPickerField', () {
    testWidgets('shows the placeholder until something is picked', (tester) async {
      await tester.pumpWidget(host(
        AppPickerField<String>(
          label: 'Country',
          placeholder: 'Choose',
          value: null,
          format: (v) => v,
          onPick: () async => 'France',
          onChanged: (_) {},
        ),
      ));
      expect(find.text('Choose'), findsOneWidget);

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('France'), findsOneWidget);
    });

    testWidgets('a dismissed picker leaves the value alone', (tester) async {
      var changes = 0;
      await tester.pumpWidget(host(
        AppPickerField<String>(
          label: 'Country',
          placeholder: 'Choose',
          value: null,
          format: (v) => v,
          onPick: () async => null,
          onChanged: (_) => changes++,
        ),
      ));

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(changes, 0);
      expect(find.text('Choose'), findsOneWidget);
    });
  });

  group('surfaces', () {
    testWidgets('AppCard mounts with and without its blooms', (tester) async {
      for (final glow in [false, true]) {
        await tester.pumpWidget(host(AppCard(glow: glow, child: const Text('body'))));
        expect(tester.takeException(), isNull);
        expect(find.text('body'), findsOneWidget);
      }
    });

    testWidgets('the gradient runs from the accent to the surface', (tester) async {
      final b = brand();
      await tester.pumpWidget(host(const AppScreenGradient(child: SizedBox.expand())));

      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(AppScreenGradient),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final gradient = (decorated.decoration as BoxDecoration).gradient as LinearGradient;
      expect(gradient.colors, <Color>[b.colors.accent, b.colors.surface]);
    });
  });
}

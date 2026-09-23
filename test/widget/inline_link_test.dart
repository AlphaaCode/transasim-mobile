import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/i18n/strings.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/app_button.dart';

import 'real_fonts.dart';

/// Reported from a phone: the sign-in footer read
///
/// ```
///       Pas encore de
///   compte ?  Créer le compte
/// ```
///
/// It was a Row of a Text and a TextButton, and a Row can only break BETWEEN
/// its children — so the prompt wrapped inside its own Flexible. One text block
/// breaks where a sentence breaks, which at these widths means not at all.

/// The width the footer really gets inside the sign-in card on a 360dp phone:
/// 360 less the list's 16 each side and the card's 24 each side.
const double _innerWidthOn360 = 360 - (Gap.lg * 2) - (Gap.xl * 2);

final BrandConfig _sabily = () {
  final json = jsonDecode(File('brands/sabily/brand.json').readAsStringSync());
  return BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'sabily').config
      as BrandConfig;
}();

Future<int> _linesAt(WidgetTester tester, double width,
    {required String prompt, required String action, VoidCallback? onPressed}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(_sabily),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: AppInlineLink(
            prompt: prompt,
            action: action,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return _lines(tester);
}

/// How many lines the one paragraph actually drew.
///
/// Counted by merging the glyph boxes that overlap vertically, NOT by grouping
/// equal `top` values: the prompt is 16px and the link 14px, so two runs on the
/// same line have different tops and naive grouping reports four lines for one.
int _lines(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: paragraph.text.toPlainText().length),
  )..sort((a, b) => a.top.compareTo(b.top));

  var lines = 0;
  var lineBottom = double.negativeInfinity;
  for (final box in boxes) {
    // A box starting below everything placed so far begins a new line.
    if (box.top >= lineBottom) {
      lines++;
      lineBottom = box.bottom;
    } else if (box.bottom > lineBottom) {
      lineBottom = box.bottom;
    }
  }
  return lines;
}

void main() {
  // Without the real typefaces the test binding measures a fixed-width stand-in
  // font, where every glyph is a square em: "Pas encore de compte ?" alone
  // "needs" 600px and the answer would be about a font the app never ships.
  setUpAll(loadRealFonts);

  testWidgets('the French footer is one line in the width it actually gets', (tester) async {
    final fr = kStrings['fr']!;
    expect(
      await _linesAt(
        tester,
        _innerWidthOn360,
        prompt: fr['account.noAccountPrompt']!,
        action: fr['account.createAccount']!,
      ),
      1,
      reason: '"${fr['account.noAccountPrompt']} ${fr['account.createAccount']}" must not wrap',
    );
  });

  testWidgets('every served language fits, on both footers', (tester) async {
    // The sign-in footer and the register screen's, which is the same widget
    // with the other sentence. German is the long one.
    final tooTall = <String>[];
    for (final language in _sabily.locales) {
      final strings = kStrings[language]!;
      for (final pair in [
        ('account.noAccountPrompt', 'account.createAccount'),
        ('account.haveAccountPrompt', 'account.signIn'),
      ]) {
        final lines = await _linesAt(
          tester,
          _innerWidthOn360,
          prompt: strings[pair.$1]!,
          action: strings[pair.$2]!,
        );
        if (lines > 1) tooTall.add('$language ${pair.$1}: $lines lines');
      }
    }
    expect(tooTall, isEmpty);
  });

  testWidgets('a narrow phone wraps as a sentence, not between the two halves', (tester) async {
    // 280dp is the design floor; at 200 something has to give. What matters is
    // that it stays ONE paragraph — the failure being fixed was a break with
    // the prompt hanging above the link.
    final fr = kStrings['fr']!;
    final lines = await _linesAt(
      tester,
      200,
      prompt: fr['account.noAccountPrompt']!,
      action: fr['account.createAccount']!,
    );
    expect(lines, greaterThan(1));
    expect(find.byType(RichText), findsOneWidget, reason: 'still one text block');
  });

  testWidgets('the action is still tappable', (tester) async {
    var taps = 0;
    final fr = kStrings['fr']!;
    await _linesAt(
      tester,
      _innerWidthOn360,
      prompt: fr['account.noAccountPrompt']!,
      action: fr['account.createAccount']!,
      onPressed: () => taps++,
    );

    // On the link itself, not on the prompt: the whole line must not be a
    // button, or a mis-tap on "Pas encore de compte ?" leaves the screen.
    final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
    final size = paragraph.size;
    await tester.tapAt(paragraph.localToGlobal(Offset(size.width - 12, size.height / 2)));
    await tester.pump();
    expect(taps, 1);

    await tester.tapAt(paragraph.localToGlobal(Offset(4, size.height / 2)));
    await tester.pump();
    expect(taps, 1, reason: 'the prompt is prose, not a control');
  });
}

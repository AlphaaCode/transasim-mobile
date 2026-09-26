import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/account/presentation/profile_screen.dart';

/// Reported from a phone: the language picker overflowed by 6.7px, clipping
/// the last language in the list.
///
/// The cause is not the content — the Column is `mainAxisSize.min` and asks
/// for exactly its rows. It is `showModalBottomSheet`, which without
/// `isScrollControlled` caps a sheet at 9/16 of the screen. Sabily's seven
/// 56px rows plus the gesture-navigation inset do not fit in that.
///
/// This matters beyond the yellow stripes: an overflow paints the warning in
/// debug and silently CLIPS in release, so a tester on a small phone would
/// simply never see the last language.

final BrandConfig _sabily = () {
  final json = jsonDecode(File('brands/sabily/brand.json').readAsStringSync());
  return BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'sabily').config
      as BrandConfig;
}();

Future<void> _openPicker(WidgetTester tester, {required Size screen}) async {
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3;
  // A phone with gesture navigation: the inset the sheet must also fit inside.
  tester.view.padding = const FakeViewPadding(bottom: 48 * 3, top: 24 * 3);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(_sabily),
      sharedPreferencesProvider.overrideWithValue(prefs),
      allModulesProvider.overrideWithValue(const []),
    ],
    child: MaterialApp(
      theme: buildTheme(_sabily),
      home: const ProfileScreen(),
    ),
  ));
  await tester.pumpAndSettle();

  await _tapLanguageRow(tester);
}

/// The row can sit below the fold on a short screen or at a large text scale,
/// so it is scrolled to rather than assumed visible.
Future<void> _tapLanguageRow(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byIcon(Icons.language), 120);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.language));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every language this brand serves is reachable, and nothing overflows',
      (tester) async {
    // 360x640 is the small end of phones still in use, and the size where the
    // 9/16 cap bites hardest.
    await _openPicker(tester, screen: const Size(360, 640));

    // Any framework error fails here, which is the point: this screen used to
    // raise two at once — the sheet overflowing, and four ListTile ink
    // assertions from the section card. Both are fixed, so silence is real.
    expect(tester.takeException(), isNull, reason: 'the sheet overflowed its constraints');

    // All seven, including the last one — the one that was being clipped.
    // `findsWidgets`, not `findsOneWidget`: the row underneath also shows the
    // current language as its subtitle, so "English" legitimately appears
    // twice while the sheet is open.
    for (final code in _sabily.locales) {
      final endonym = kLanguageEndonyms[code] ?? code;
      expect(find.text(endonym), findsWidgets, reason: endonym);
    }
    expect(find.text(kLanguageEndonyms['sq']!), findsOneWidget, reason: 'Shqip was the casualty');
  });

  testWidgets('a taller phone is fine too, and the list still fits', (tester) async {
    await _openPicker(tester, screen: const Size(360, 780));
    expect(tester.takeException(), isNull);
    expect(find.text(kLanguageEndonyms['sq']!), findsWidgets);
  });

  testWidgets('at the largest font scale the rows scroll instead of overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 48 * 3, top: 24 * 3);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(_sabily),
        sharedPreferencesProvider.overrideWithValue(prefs),
        allModulesProvider.overrideWithValue(const []),
      ],
      child: MaterialApp(
        theme: buildTheme(_sabily),
        home: MediaQuery(
          // Accessibility text scaling, which makes every row taller than the
          // 56 the arithmetic above assumes.
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const ProfileScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await _tapLanguageRow(tester);

    expect(tester.takeException(), isNull, reason: 'must scroll, not overflow');
    // The first language is reachable; the rest are a scroll away, which is
    // the correct behaviour when the content genuinely exceeds the screen.
    expect(find.text(kLanguageEndonyms[_sabily.locales.first]!), findsOneWidget);
  });
}

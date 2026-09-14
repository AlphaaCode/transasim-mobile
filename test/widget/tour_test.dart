import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/onboarding/tour.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/app_coach_mark.dart';

BrandConfig _sabily() {
  final json =
      jsonDecode(File('brands/sabily/brand.json').readAsStringSync()) as Map<String, dynamic>;
  return BrandConfig.parse(json, expectedSlug: 'sabily').config as BrandConfig;
}

/// A screen with two real targets, one far enough down a list to need a scroll.
class _Screen extends ConsumerStatefulWidget {
  final GlobalKey top;
  final GlobalKey below;
  const _Screen({required this.top, required this.below});

  @override
  ConsumerState<_Screen> createState() => _ScreenState();
}

class _ScreenState extends ConsumerState<_Screen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          children: [
            SizedBox(key: widget.top, height: 60, child: const Text('top target')),
            // Off screen, but inside the list's cache extent, so it is built.
            const SizedBox(height: 700),
            SizedBox(key: widget.below, height: 60, child: const Text('below target')),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => runTour(context, ref, [
            (TourStep.scanVoucher, CoachMark(target: widget.top, title: 'T1', body: 'B1')),
            (TourStep.store, CoachMark(target: widget.below, title: 'T2', body: 'B2')),
          ]),
        ),
      );
}

Future<(ProviderContainer, GlobalKey, GlobalKey)> _pump(
  WidgetTester tester,
  SharedPreferences prefs,
) async {
  final brand = _sabily();
  final top = GlobalKey();
  final below = GlobalKey();
  final container = ProviderContainer(overrides: [
    brandConfigProvider.overrideWithValue(brand),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: buildTheme(brand), home: _Screen(top: top, below: below)),
  ));
  return (container, top, below);
}

/// The tour waits for the logo intro. These tests are about the tour, so the
/// intro is already behind them, as it is on every launch after the first.
const _introSeen = 'intro.seen';

Rect _rectOf(WidgetTester tester, GlobalKey key) =>
    tester.getRect(find.byKey(key));

void main() {
  testWidgets('the bubble points at the real widget, scrolling to it when needed', (tester) async {
    SharedPreferences.setMockInitialValues({_introSeen: true});
    final prefs = await SharedPreferences.getInstance();
    final (container, top, below) = await _pump(tester, prefs);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsOneWidget);
    // The hole is the target's own bounds, measured, not a guess.
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<CustomPainter>()
        .firstWhere((p) => p.runtimeType.toString() == '_ScrimPainter');
    expect((painter as dynamic).hole, _rectOf(tester, top).inflate(6));

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('T2'), findsOneWidget);
    // The second target started off screen; it had to be scrolled on screen.
    final belowRect = _rectOf(tester, below);
    expect(belowRect.top, greaterThanOrEqualTo(0));
    expect(belowRect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));

    await tester.tap(find.text("J'ai compris"));
    await tester.pumpAndSettle();
    expect(find.text('T2'), findsNothing);
    expect(prefs.getStringList('tour.seen'), containsAll([TourStep.scanVoucher, TourStep.store]));
  });

  testWidgets('skip ends the whole tour, and it does not come back', (tester) async {
    SharedPreferences.setMockInitialValues({_introSeen: true});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsNothing);
    expect(prefs.getBool('tour.done'), isTrue);

    // A fresh start of the app, same device.
    await _pump(tester, prefs);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsNothing);
  });

  testWidgets('a mark already seen is not shown again', (tester) async {
    SharedPreferences.setMockInitialValues({
      _introSeen: true,
      'tour.seen': [TourStep.scanVoucher],
    });
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsNothing);
    expect(find.text('T2'), findsOneWidget);
  });

  test('the tour is done only when every mark has been seen', () async {
    SharedPreferences.setMockInitialValues({_introSeen: true});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final tour = c.read(tourProvider.notifier);

    for (final step in TourStep.all.take(TourStep.all.length - 1)) {
      tour.markSeen(step);
    }
    expect(c.read(tourProvider).done, isFalse);
    expect(tour.isPending(TourStep.all.last), isTrue);
    tour.markSeen(TourStep.all.last);
    expect(c.read(tourProvider).done, isTrue);
    expect(prefs.getBool('tour.done'), isTrue);
  });
}

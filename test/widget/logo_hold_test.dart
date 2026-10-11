/// The logo hold: what ends it, and what it refuses to let end it.
///
/// The hold sits in front of the app at launch, so the two failure modes are
/// opposite and both bad. Too eager and a fast launch flashes the logo for a
/// few frames, which reads as a rendering glitch. Too patient and a dead
/// backend leaves a user holding a logo with no way forward. These pin both
/// bounds, with the prefetch mocked at each extreme.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/onboarding/intro.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';

BrandConfig brand(String slug) {
  final json = jsonDecode(File('brands/$slug/brand.json').readAsStringSync());
  final r = BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: slug);
  if (r.errors.isNotEmpty) throw StateError(r.describe(slug));
  return r.config as BrandConfig;
}

final _esimple = brand('esimple');

/// The hold, with the warm-up pinned to [settled].
Future<void> pumpHold(
  WidgetTester tester, {
  required bool settled,
  BrandConfig? config,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = config ?? _esimple;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(c),
      sharedPreferencesProvider.overrideWithValue(prefs),
      allModulesProvider.overrideWithValue(const []),
      appWarmupSettledProvider.overrideWithValue(settled),
    ],
    child: MaterialApp(
      theme: buildTheme(c),
      home: const IntroGate(child: Scaffold(body: Text('APP'))),
    ),
  ));
  await tester.pump();
}

/// The app underneath is built from the first frame; what the hold does is
/// cover it. So "still holding" is the logo being on screen, not the app
/// being absent.
bool holding(WidgetTester tester) => tester.any(find.byType(Image));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eSimple is configured the way these tests assume', () {
    expect(_esimple.intro.style, IntroStyle.logoHold);
    expect(_esimple.intro.logoHoldMin, const Duration(milliseconds: 1500));
    expect(_esimple.intro.logoHoldMax, const Duration(milliseconds: 4000));
    expect(_esimple.logo.introBackground?.toARGB32(), 0xFF000000);
  });

  group('the floor', () {
    testWidgets('a prefetch that settles instantly still holds logoHoldMinMs',
        (tester) async {
      await pumpHold(tester, settled: true);
      expect(holding(tester), isTrue, reason: 'the hold must be on screen at once');

      // 100 ms before the floor it is still there, however ready the app is.
      await tester.pump(_esimple.intro.logoHoldMin - const Duration(milliseconds: 100));
      expect(holding(tester), isTrue,
          reason: 'a ready app must not flash the logo and vanish');

      // Past the floor, plus the fade.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(holding(tester), isFalse);
      expect(find.text('APP'), findsOneWidget);
    });
  });

  group('the ceiling', () {
    testWidgets('a prefetch that never settles releases at logoHoldMaxMs',
        (tester) async {
      await pumpHold(tester, settled: false);

      // Well past the floor and still held, because the app is not ready.
      await tester.pump(_esimple.intro.logoHoldMin + const Duration(milliseconds: 500));
      expect(holding(tester), isTrue,
          reason: 'past the floor but not settled: the hold waits');

      // 100 ms short of the cap: still waiting.
      await tester.pump(const Duration(milliseconds: 1900));
      expect(holding(tester), isTrue);

      // Past the cap it leaves anyway — a dead backend must never freeze it.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(holding(tester), isFalse, reason: 'the cap did not fire');
      expect(find.text('APP'), findsOneWidget);
    });

    testWidgets('settling between the floor and the cap releases immediately',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settled = ValueNotifier<bool>(false);
      addTearDown(settled.dispose);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          brandConfigProvider.overrideWithValue(_esimple),
          sharedPreferencesProvider.overrideWithValue(prefs),
          allModulesProvider.overrideWithValue(const []),
          appWarmupSettledProvider
              .overrideWith((ref) => ref.watch(_settledProvider(settled))),
        ],
        child: MaterialApp(
          theme: buildTheme(_esimple),
          home: const IntroGate(child: Scaffold(body: Text('APP'))),
        ),
      ));
      await tester.pump();

      await tester.pump(_esimple.intro.logoHoldMin + const Duration(milliseconds: 200));
      expect(holding(tester), isTrue);

      // The catalogue comes back at 1.7 s — long before the 4 s cap.
      settled.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(holding(tester), isFalse,
          reason: 'it must leave on the prefetch, not sit out the full cap');
    });
  });

  group('what it paints', () {
    testWidgets('the brand mark on the brand launch colour, and no spinner',
        (tester) async {
      await pumpHold(tester, settled: false);

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName,
          'brands/esimple/assets/${_esimple.logo.mark}');

      final ground = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
      expect(ground.any((b) => b.color.toARGB32() == 0xFF000000), isTrue,
          reason: 'the hold must paint the same black the native splash does');

      // The brief is explicit: nothing that pretends to measure progress.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('it is opaque on its very first frame', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // Deliberately NOT pumpHold: its settling pump would hide a first frame
      // that started transparent, and the first frame is the thing under test.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          brandConfigProvider.overrideWithValue(_esimple),
          sharedPreferencesProvider.overrideWithValue(prefs),
          allModulesProvider.overrideWithValue(const []),
          appWarmupSettledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: buildTheme(_esimple),
          home: const IntroGate(child: Scaffold(body: Text('APP'))),
        ),
      ));

      // The native splash hands over with this same mark already at full
      // opacity. Fading up from zero blinked it out for a frame on a real
      // device (measured at 420 dpi), so frame one must be opaque.
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1,
          reason: 'a fade in here is a blink, not a fade');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the mark is drawn at the size the native splash used',
        (tester) async {
      await pumpHold(tester, settled: false);
      // 164 dp reproduces the 121.1 x 144.4 dp of ink Android 12+ draws, for
      // an asset whose ink is 0.7407 x 0.8796 of its canvas. Changing either
      // the number or the asset's padding without the other reintroduces the
      // jump, which is invisible in code and obvious on a phone.
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 164.0);
      expect(image.height, 164.0);
    });
  });

  group('a video brand is untouched by any of this', () {
    testWidgets('Sabily does not get a hold', (tester) async {
      final sabily = brand('sabily');
      expect(sabily.intro.style, IntroStyle.video);

      await pumpHold(tester, settled: true, config: sabily);
      // No hold widget: the video path owns the screen, and with no platform
      // video player under test it bails on its own deadline.
      expect(find.byType(AnimatedOpacity), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}

/// Bridges a [ValueNotifier] into the provider the hold watches, so a test can
/// flip "the prefetch came back" mid-hold.
final _settledProvider = Provider.family<bool, ValueNotifier<bool>>((ref, n) {
  void listener() => ref.invalidateSelf();
  n.addListener(listener);
  ref.onDispose(() => n.removeListener(listener));
  return n.value;
});

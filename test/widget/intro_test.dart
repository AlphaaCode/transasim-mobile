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

/// The intro must never stand between launch and the app. These pin the three
/// ways it gets out of the way without anyone waiting for a video to finish.

BrandConfig _brand({bool withIntro = true}) {
  final json =
      jsonDecode(File('brands/sabily/brand.json').readAsStringSync()) as Map<String, dynamic>;
  if (!withIntro) (json['logo'] as Map).remove('intro');
  return BrandConfig.parse(json, expectedSlug: 'sabily').config as BrandConfig;
}

Future<SharedPreferences> _pump(WidgetTester tester,
    {required BrandConfig brand,
    Map<String, Object> prefs = const {},
    Widget home = const Scaffold(body: Text('APP'))}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      brandConfigProvider.overrideWithValue(brand),
      sharedPreferencesProvider.overrideWithValue(p),
    ],
    child: MaterialApp(
      theme: buildTheme(brand),
      builder: (_, child) => IntroGate(child: child!),
      home: home,
    ),
  ));
  return p;
}

void main() {
  testWidgets('a brand without an intro goes straight in', (tester) async {
    await _pump(tester, brand: _brand(withIntro: false));
    expect(find.text('APP'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('it plays on every launch: a previous launch having played it changes nothing',
      (tester) async {
    // The key the once-per-install version wrote. Left on devices that ran it,
    // it must not suppress the animation now.
    await _pump(tester, brand: _brand(), prefs: {'intro.seen': true});
    expect(find.byType(GestureDetector), findsOneWidget);
  });

  testWidgets('a video that cannot play is skipped, and the app is there underneath',
      (tester) async {
    // No video platform in a widget test: initialize fails, exactly as a
    // missing codec or a corrupt asset would on a phone.
    final prefs = await _pump(tester, brand: _brand());
    expect(find.text('APP'), findsOneWidget, reason: 'built underneath from the first frame');
    expect(find.byType(GestureDetector), findsOneWidget, reason: 'the intro is covering it');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(GestureDetector), findsNothing);
    expect(prefs.getKeys(), isEmpty, reason: 'nothing is remembered between launches');
  });

  testWidgets('what waits on the intro runs only once it is over', (tester) async {
    await _pump(tester, brand: _brand(), home: const _WaitsForIntro());
    expect(find.text('WAITING'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('RAN'), findsOneWidget);
  });
}

class _WaitsForIntro extends ConsumerStatefulWidget {
  const _WaitsForIntro();
  @override
  ConsumerState<_WaitsForIntro> createState() => _WaitsForIntroState();
}

class _WaitsForIntroState extends ConsumerState<_WaitsForIntro> {
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    untilIntroDone(ref).then((_) => mounted ? setState(() => _ran = true) : null);
  }

  @override
  Widget build(BuildContext context) => Text(_ran ? 'RAN' : 'WAITING');
}

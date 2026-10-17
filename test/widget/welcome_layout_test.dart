import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/storage/preferences.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/core/ui/app_card.dart';
import 'package:transasim_mobile/modules/account/domain/account.dart';
import 'package:transasim_mobile/modules/account/presentation/account_controllers.dart';
import 'package:transasim_mobile/modules/account/presentation/auth_screens.dart';

import '../core/session_test.dart' show SpyStorage;
import 'real_fonts.dart';

class _NoAccount implements AccountRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// On a 16:9 phone (1080×1920, 411×731 dp) Acorn's welcome title wraps to two
/// lines, and its second one sat under the sheet (2026-10-17). The badge now
/// gives way first, so the words stay in view.
void main() {
  setUpAll(loadRealFonts);

  testWidgets('a long brand name stays above the sheet on a 16:9 phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final json = jsonDecode(File('brands/acorn/brand.json').readAsStringSync()) as Map<String, dynamic>;
    final brand = BrandConfig.parse(json, expectedSlug: 'acorn').config as BrandConfig;
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.625;
    // The emulator's status bar and gesture bar, 24 dp each: without them this
    // screen has room the phone does not, and the old layout passes.
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        brandConfigProvider.overrideWithValue(brand),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionStoreProvider.overrideWithValue(SessionStore(storage: SpyStorage())),
        accountRepositoryProvider.overrideWithValue(_NoAccount()),
      ],
      child: MaterialApp.router(
        theme: buildTheme(brand),
        routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const WelcomeScreen())]),
      ),
    ));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(AppBottomSheetCard)).top;
    expect(tester.getRect(find.text('Welcome to Odyssey Global SIM')).bottom, lessThanOrEqualTo(sheet));
    expect(tester.getRect(find.text('Your journey starts here.')).bottom, lessThanOrEqualTo(sheet));
    expect(tester.getSize(find.byType(AppLogoBadge)).height, inExclusiveRange(96, 192),
        reason: 'smaller than its 192, not yet at its 96 floor');
  });
}

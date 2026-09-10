import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand/brand_config.dart';
import '../../core/modules/app_module.dart';
import 'presentation/wallet_screen.dart';

/// The TransaPay skeleton. ARCHITECTURE-MOBILE.md §4.3.
///
/// It is a DELIVERABLE, and it is empty: one route, a "coming soon" screen, a
/// flag, and zero logic. Its job is to prove the extension point works before
/// TransaPay exists — an extension point that is never exercised is an
/// extension point that does not work.
///
/// It is also the only optional module in the socle, because `features.wallet`
/// is the only flag the code reads (§2.6). There is no reseller module: mobile
/// is BtoC only (§0).
class WalletModule extends AppModule {
  const WalletModule();

  @override
  String get id => 'wallet';

  @override
  bool isEnabled(BrandConfig config) => config.features.wallet;

  @override
  List<RouteBase> routes(BrandConfig config) => <RouteBase>[
        GoRoute(
          path: '/wallet',
          name: 'wallet',
          builder: (context, state) => const WalletScreen(),
        ),
      ];

  @override
  List<NavEntry> navEntries(BrandConfig config) => const <NavEntry>[
        NavEntry(
          moduleId: 'wallet',
          path: '/wallet',
          labelKey: 'nav.wallet',
          icon: Icons.account_balance_wallet_outlined,
        ),
      ];
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand/brand_config.dart';
import '../../core/modules/app_module.dart';
import 'presentation/home_screen.dart';

/// The first screen.
///
/// ⚠️ THE ONE SCREEN IN THIS APP WITH NO DESIGN SOURCE. Every other screen was
/// pulled from a Sabily-branded Figma frame via `get_design_context`; this one
/// does not exist in the file. It is composed entirely from the existing
/// component layer and brand tokens — no new style is invented here — but the
/// LAYOUT and the ordering are a judgement call and should get a look from
/// design before it is treated as settled.
///
/// The judgement being made: "Scan your voucher" is the hero rather than a
/// catalogue tile, because Sabily's customers are Hajj and Umrah pilgrims who
/// commonly arrive with an agency-issued voucher already in hand.
class HomeModule extends AppModule {
  const HomeModule();

  @override
  String get id => 'home';

  @override
  bool isEnabled(BrandConfig config) => true;

  @override
  List<RouteBase> routes(BrandConfig config) => <RouteBase>[
        GoRoute(
          path: '/home',
          name: 'home',
          builder: (context, state) => const HomeScreen(),
        ),
      ];

  @override
  List<NavEntry> navEntries(BrandConfig config) => const <NavEntry>[
        NavEntry(
          moduleId: 'home',
          path: '/home',
          labelKey: 'nav.home',
          icon: Icons.home_outlined,
        ),
      ];
}

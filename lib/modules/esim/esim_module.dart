import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand/brand_config.dart';
import '../../core/modules/app_module.dart';
import 'presentation/esim_screens.dart';

/// The eSIMs a subscriber owns, and how to install one.
///
/// Always active: there is no `features.esim`, because nothing would read it.
/// A flag no code consults is a delayed lie (§2.6).
class EsimModule extends AppModule {
  const EsimModule();

  @override
  String get id => 'esim';

  @override
  bool isEnabled(BrandConfig config) => true;

  @override
  List<RouteBase> routes(BrandConfig config) => <RouteBase>[
        GoRoute(
          path: '/esims',
          name: 'esims',
          builder: (context, state) => const MyEsimsScreen(),
        ),
        // Outside the tab shell, like the destination screen: the detail is a
        // task, and the design gives it its own header.
        GoRoute(
          path: '/esims/:id',
          name: 'esimDetail',
          builder: (context, state) => EsimDetailScreen(
            id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
          ),
        ),
      ];

  @override
  List<NavEntry> navEntries(BrandConfig config) => const <NavEntry>[
        NavEntry(
          moduleId: 'esim',
          path: '/esims',
          labelKey: 'nav.esims',
          icon: Icons.sim_card_outlined,
        ),
      ];
}

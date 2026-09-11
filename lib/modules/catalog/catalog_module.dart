import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand/brand_config.dart';
import '../../core/modules/app_module.dart';
import 'presentation/destination_screen.dart';
import 'presentation/store_screen.dart';

/// Discovery: destinations, search, and the packs for one destination.
///
/// Always active — there is no `features.catalog`, because nothing would read
/// it. A flag that no code consults is a delayed lie (§2.6).
class CatalogModule extends AppModule {
  const CatalogModule();

  @override
  String get id => 'catalog';

  @override
  bool isEnabled(BrandConfig config) => true;

  @override
  List<RouteBase> routes(BrandConfig config) => <RouteBase>[
        GoRoute(
          path: '/store',
          name: 'store',
          builder: (context, state) => const StoreScreen(),
        ),
        // Deliberately NOT a nav entry: the design gives this screen a
        // task-focused header that suppresses the main navigation, so the
        // router keeps it outside the tab shell.
        GoRoute(
          path: '/destination/:code',
          name: 'destination',
          builder: (context, state) =>
              DestinationScreen(code: state.pathParameters['code'] ?? ''),
        ),
      ];

  @override
  List<NavEntry> navEntries(BrandConfig config) => const <NavEntry>[
        NavEntry(
          moduleId: 'catalog',
          path: '/store',
          labelKey: 'nav.store',
          icon: Icons.storefront_outlined,
        ),
      ];
}

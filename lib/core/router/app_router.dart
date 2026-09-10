import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../brand/brand_providers.dart';
import '../dev/brand_preview_screen.dart';

/// The router is assembled from the ACTIVE modules only.
///
/// ARCHITECTURE-MOBILE.md §4.2: a disabled module's routes are never
/// registered, so its deep links resolve to nothing. That is half of what makes
/// a flag honest; `ModuleRegistry.guard` is the other half.
///
/// The old app's router was a 151-line `switch` with every route unconditional
/// and untyped `Map<String, dynamic>` arguments
/// (`ANALYSE-EXISTANT.md` §2.2).
final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  final brand = ref.watch(brandConfigProvider);

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const BrandPreviewScreen(),
      ),
      ...registry.routes,
    ],
    // A deep link into a disabled module lands here, not on its screen.
    errorBuilder: (context, state) => const BrandPreviewScreen(),
    debugLogDiagnostics: false,
    restorationScopeId: 'app_${brand.slug}',
  );
});

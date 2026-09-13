import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../brand/brand_providers.dart';
import '../dev/brand_preview_screen.dart';
import '../onboarding/tour.dart';
import '../theme/app_theme.dart';

/// The router is assembled from the ACTIVE modules only.
///
/// ARCHITECTURE-MOBILE.md §4.2: a disabled module's routes are never
/// registered, so its deep links resolve to nothing. That is half of what makes
/// a flag honest; `ModuleRegistry.guard` is the other half.
///
/// Routes are partitioned by a single rule, so the `AppModule` contract did not
/// need a second list: a route whose path matches one of the module's own nav
/// entries lives INSIDE the tab shell; everything else is top-level. That is
/// what lets a task-focused screen suppress the main navigation the way the
/// destination screen's design does.
final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  final brand = ref.watch(brandConfigProvider);

  final navPaths = registry.navEntries.map((e) => e.path).toSet();
  final tabbed = <RouteBase>[];
  final standalone = <RouteBase>[];
  for (final route in registry.routes) {
    final isTab = route is GoRoute && navPaths.contains(route.path);
    (isTab ? tabbed : standalone).add(route);
  }

  final home = registry.navEntries.isEmpty ? '/preview' : registry.navEntries.first.path;

  return GoRouter(
    initialLocation: home,
    routes: [
      // Kept reachable after the catalogue takes over `/`: it is the QA surface
      // and where the version marker lives (§9.7).
      GoRoute(
        path: '/preview',
        name: 'preview',
        builder: (context, state) => const BrandPreviewScreen(),
      ),
      if (tabbed.isNotEmpty)
        ShellRoute(
          builder: (context, state, child) => _AppShell(child: child),
          routes: tabbed,
        ),
      ...standalone,
    ],
    // A deep link into a disabled module lands here rather than on its screen.
    errorBuilder: (context, state) => const BrandPreviewScreen(),
    restorationScopeId: 'app_${brand.slug}',
  );
});

/// The tab shell. Its destinations come from the active modules, so the tab set
/// is a configuration outcome — the white-label template has three tabs where
/// Sabily has four, and neither is a special case (§5.7).
class _AppShell extends ConsumerWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(moduleRegistryProvider).navEntries;
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final location = GoRouterState.of(context).uri.path;
    final index = entries.indexWhere((e) => location.startsWith(e.path));

    if (entries.length < 2) return child;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(entries[i].path),
        backgroundColor: t.card,
        indicatorColor: t.accent,
        destinations: [
          for (final e in entries)
            // Keyed so the onboarding tour can point at the real tab.
            KeyedSubtree(
              key: ref.watch(navAnchorProvider(e.labelKey)),
              child: NavigationDestination(
                icon: Icon(e.icon),
                // The label is a dictionary key resolved here — modules never
                // carry human-readable strings.
                label: l10n.t(e.labelKey),
              ),
            ),
        ],
      ),
    );
  }
}

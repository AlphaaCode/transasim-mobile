import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_skeleton.dart';
import '../../../core/ui/app_text_field.dart';
import 'catalog_controllers.dart';
import 'widgets.dart';

/// The Store tab: every destination with a purchasable pack.
///
/// Follows `eSIM Catalog - Sabily (Mobile).png` and `Regional Packs - Sabily
/// (Mobile).png` for structure — a title block, a search field, then the list.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final async = ref.watch(catalogControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('nav.store'))),
      body: SafeArea(
        child: async.when(
          loading: () => const _StoreSkeleton(),
          error: (e, _) => StateMessage(
            icon: Icons.error_outline,
            title: l10n.t('error.generic'),
            actionLabel: l10n.t('common.retry'),
            onAction: () => ref.read(catalogControllerProvider.notifier).refresh(),
          ),
          data: (state) => switch (state) {
            CatalogLoading() => const _StoreSkeleton(),
            CatalogFailed(:final error) => StateMessage(
                icon: Icons.cloud_off,
                // Typed error -> dictionary key. Never a raw exception string.
                title: l10n.t('error.${error.code}', vars: const {}),
                actionLabel: l10n.t('common.retry'),
                onAction: () => ref.read(catalogControllerProvider.notifier).refresh(),
              ),
            CatalogReady() => _Loaded(state: state),
          },
        ),
      ),
      backgroundColor: t.surface,
    );
  }
}

class _Loaded extends ConsumerWidget {
  final CatalogReady state;
  const _Loaded({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    // Slivers, not a ListView of children: the old form built a tile for every
    // destination on every rebuild — so every keystroke in the search box
    // constructed the entire catalogue, visible or not. With a builder only
    // the rows on screen exist.
    return RefreshIndicator(
      onRefresh: () => ref.read(catalogControllerProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('catalog.title'), style: AppType.title.copyWith(color: t.primary)),
                  const SizedBox(height: Gap.xs),
                  Text(l10n.t('catalog.subtitle'),
                      style: AppType.body.copyWith(color: t.inkMuted)),
                  const SizedBox(height: Gap.lg),
                  AppSearchField(
                    hint: l10n.t('catalog.searchHint'),
                    initialValue: state.query,
                    onChanged: ref.read(catalogControllerProvider.notifier).search,
                  ),
                  const SizedBox(height: Gap.lg),
                ],
              ),
            ),
          ),
          if (state.regions.length > 1)
            SliverToBoxAdapter(child: _RegionChips(state: state)),
          if (state.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: Gap.xxl),
              sliver: SliverToBoxAdapter(
                child: StateMessage(
                  icon: Icons.search_off,
                  title: l10n.t('catalog.emptyTitle'),
                  body: l10n.t('catalog.emptyBody'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
              sliver: SliverList.builder(
                itemCount: state.visible.length,
                // A stable key per destination, so a search that filters the
                // list reuses the rows that survived instead of rebuilding all
                // of them against shifted indices.
                findChildIndexCallback: (key) {
                  final code = (key as ValueKey<String>).value;
                  final i = state.visible.indexWhere((d) => d.code == code);
                  return i < 0 ? null : i;
                },
                itemBuilder: (context, i) {
                  final destination = state.visible[i];
                  return DestinationTile(
                    key: ValueKey<String>(destination.code),
                    destination: destination,
                    onTap: () => context.pushNamed(
                      'destination',
                      pathParameters: {'code': destination.code},
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Filter Section, White-Label Store Template (66:54): All, then one chip per
/// region the catalogue sells into.
///
/// It filters DESTINATIONS, which is what this screen lists. The template
/// draws the chips over a grid of packs, but a pack here belongs to one or to
/// 175 countries, so "the region of a pack" has no single answer; the region of
/// a destination does.
class _RegionChips extends ConsumerWidget {
  final CatalogReady state;
  const _RegionChips({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final select = ref.read(catalogControllerProvider.notifier).selectRegion;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Side padding matches the list below so the first chip lines up with
      // the cards; 8 below is the template's.
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm + Gap.lg),
      child: Row(
        children: [
          for (final region in <Region?>[null, ...state.regions]) ...[
            if (region != null) const SizedBox(width: Gap.md),
            _Chip(
              label: l10n.t('catalog.region.${region?.name ?? 'all'}'),
              selected: state.region == region,
              onTap: () => select(region),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final shape = StadiumBorder(
      side: selected ? BorderSide.none : BorderSide(color: t.fieldBorder),
    );

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? t.primary : t.chipSurface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            // 16 x 9 selected; unselected carries a 1px border inside the same
            // outer size, as the template does (17 x 9 there, border included).
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 9),
            child: Text(
              label,
              style: AppType.chip.copyWith(color: selected ? t.onPrimary : t.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// The store's loading state, shaped like the store.
class _StoreSkeleton extends ConsumerWidget {
  const _StoreSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppListSkeleton(
        header: const [
          AppSkeletonBox(height: 32, width: 220),
          SizedBox(height: Gap.sm),
          AppSkeletonBox(height: 16, width: 280),
          SizedBox(height: Gap.lg),
          AppSkeletonBox(height: kAppFieldHeight, radius: Radii.control),
          SizedBox(height: Gap.lg),
        ],
      );
}

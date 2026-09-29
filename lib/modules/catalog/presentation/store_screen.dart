import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/i18n/country_flags.dart';
import '../../../core/i18n/country_names.dart';
import '../../../core/ui/flag_glyph.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/destination_card.dart';
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
      appBar: AppBar(
        title: Text(l10n.t('nav.store')),
        // A band a shade deeper than the page, so the title reads as a header
        // rather than as the first line of the list.
        backgroundColor: t.headerBand,
        actions: [
          // How big the catalogue is, from the catalogue itself. Rounded DOWN
          // to a round number and suffixed "+": the exact count moves every
          // time the backend adds a country, and "204 destinations" invites
          // someone to check.
          if (async.value case CatalogReady(:final destinations)) ...[
            _CountPill(count: destinations.length),
            const SizedBox(width: Gap.lg),
          ],
        ],
      ),
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
    final browsing = state.query.trim().isEmpty && state.region == null;
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
                  Text(
                    l10n.t('catalog.title'),
                    style: AppType.title.copyWith(color: ShopTokens.of(context).display),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(l10n.t('catalog.subtitle'), style: AppType.body.copyWith(color: t.inkMuted)),
                  const SizedBox(height: Gap.lg),
                  AppSearchField(
                    hint: l10n.t('catalog.searchHint'),
                    initialValue: state.query,
                    onChanged: ref.read(catalogControllerProvider.notifier).search,
                  ),
                  const SizedBox(height: Gap.md),
                  // A trip through several countries starts here, above the
                  // one-destination list it would otherwise be guessed from.
                  AppFeatureCard(
                    icon: Icons.travel_explore,
                    // The one card on this screen that is an offer rather
                    // than a destination, so it is the one that does not
                    // look like the white rows above and below it: an accent
                    // panel with the glyph inverted onto an ink tile.
                    gradient: t.accentGradient,
                    tileColor: t.primary,
                    iconColor: t.accent,
                    title: l10n.t('trip.entryTitle'),
                    body: l10n.t('trip.entryBody'),
                    trailing: Icon(Icons.chevron_right, color: t.primary),
                    onTap: () => context.pushNamed('trip'),
                  ),
                  // The shelf is a BROWSING aid, so it is only there while
                  // the user is browsing. Left up during a search it kept
                  // offering France to someone who had typed "Japan", which
                  // reads as the filter having failed.
                  if (browsing) ...[
                    const SizedBox(height: Gap.xl),
                    AppEyebrow(l10n.t('catalog.popularEyebrow')),
                    const SizedBox(height: Gap.md),
                  ] else
                    // Every gap below the card used to live inside the
                    // `browsing` branch above, and this sliver's own padding
                    // closes at 0 — so the moment a region was picked or a
                    // search typed, the shelf went away and took the spacing
                    // with it, leaving the chip row jammed against the card.
                    // The gap belongs to the header, not to the shelf.
                    const SizedBox(height: Gap.xl),
                ],
              ),
            ),
          ),
          if (browsing) ...[
            SliverToBoxAdapter(child: _PopularStrip(state: state)),
            const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
          ],
          if (state.regions.length > 1) SliverToBoxAdapter(child: _RegionChips(state: state)),
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
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.md),
              sliver: SliverToBoxAdapter(child: AppEyebrow(l10n.t('catalog.allDestinations'))),
            ),
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
                  final cheapest = destination.cheapestPrice;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: DestinationCard(
                      key: ValueKey<String>('card-${destination.code}'),
                      code: destination.code,
                      title: countryName(
                        destination.code,
                        l10n.language,
                        fallback: destination.name,
                      ),
                      subtitle: l10n.t(
                        'catalog.packCount',
                        vars: {'count': '${destination.packs.length}'},
                      ),
                      price: cheapest?.format(l10n.language),
                      priceCaption: l10n.t('catalog.from'),
                      actionLabel: l10n.t('catalog.select'),
                      onTap: () => context.pushNamed(
                        'destination',
                        pathParameters: {'code': destination.code},
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "200+ destinations", on the header band.
class _CountPill extends ConsumerWidget {
  final int count;
  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    // Down to the nearest fifty, never up: a claim about how much is on offer
    // has to stay true the day a country is withdrawn.
    final rounded = (count ~/ 50) * 50;
    if (rounded < 50) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: Shadows.badge,
      ),
      child: Text(
        l10n.t('catalog.destinationCount', vars: {'count': '$rounded'}),
        style: AppType.captionStrong.copyWith(color: t.primary),
      ),
    );
  }
}

/// A short, horizontally scrolling shelf above the full list.
///
/// "Popular" is a judgement the backend does not make: no endpoint ranks
/// destinations and nothing in `brand.json` curates them. The proxy is the
/// catalogue's own shape — the destinations that sell the most packs are the
/// ones the operator has invested the most coverage in — which is honest,
/// needs no new data, and follows the catalogue when it changes. A curated
/// list belongs in the brand config the day a client wants to choose.
class _PopularStrip extends ConsumerWidget {
  final CatalogReady state;
  const _PopularStrip({required this.state});

  static const int _count = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final language = ref.watch(languageProvider);

    // The brand's own list first, in the order it wrote them, keeping only
    // the ones this catalogue actually sells. Falling back to pack count is
    // the last resort, and a poor one — see BrandMobile.popularDestinations.
    final curated = ref.watch(brandConfigProvider.select((b) => b.mobile.popularDestinations));
    final byCode = {for (final d in state.destinations) d.code.toUpperCase(): d};
    final picks = curated.isEmpty
        ? ([
            ...state.destinations,
          ]..sort((a, b) => b.packs.length.compareTo(a.packs.length))).take(_count).toList()
        : [for (final code in curated) ?byCode[code.toUpperCase()]].take(_count).toList();
    if (picks.isEmpty) return const SizedBox.shrink();

    // The brand's own card ground, the same image the rest of the shelf uses.
    // A brand that ships none keeps the painted accent.
    final brand = ref.watch(brandConfigProvider);
    final bg = brand.mobile.cardBackground;
    final background = bg == null ? null : brand.assetPath(bg);

    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        itemCount: picks.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
        itemBuilder: (context, i) {
          final d = picks[i];
          final flag = countryFlagAsset(d.code);
          final price = d.cheapestPrice;
          return _PopularCard(
            background: background,
            flag: flag,
            code: d.code,
            name: countryName(d.code, language, fallback: d.name),
            price: price == null ? null : '${l10n.t('catalog.from')} ${price.format(language)}',
            onTap: () => context.pushNamed('destination', pathParameters: {'code': d.code}),
          );
        },
      ),
    );
  }
}

class _PopularCard extends ConsumerWidget {
  /// The brand's card ground, already resolved by the caller through
  /// `BrandConfig.assetPath` — the same helper the logos go through, and the
  /// only place a client slug is ever joined to a filename.
  final String? background;
  final String? flag;
  final String code;
  final String name;
  final String? price;
  final VoidCallback onTap;

  const _PopularCard({
    required this.background,
    required this.flag,
    required this.code,
    required this.name,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.tile);

    // Measured, not assumed: against white, Sabily's ground scores 7.9:1 and
    // eSimple's 6.0:1, but Odyssey's is far brighter at 3.2:1 and worse still
    // in its bright regions. So the text is white AND carries the scrim and
    // shadows — white alone would fail on the third brand.
    final onImage = background != null;

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: Shadows.badge),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: onImage ? t.primary : t.accent,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 128,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  if (background != null)
                    Positioned.fill(
                      child: Image.asset(
                        background!,
                        fit: BoxFit.cover,
                        // A brand whose file is missing must not take the
                        // shelf down with it; the Material colour shows.
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  if (onImage)
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[ArtInk.scrimNone, ArtInk.scrimStrong],
                            // Full strength by 55%, not at the very
                            // bottom: the name sits around 64% and
                            // Sabily's gold arcs run straight through
                            // it. Measured on device, a ramp that only
                            // finishes at 1.0 leaves the worst
                            // crossings at 2.3:1.
                            stops: <double>[0.1, 0.55],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 44,
                          child: flag == null
                              ? Text(
                                  code,
                                  style: AppType.title.copyWith(
                                    color: onImage ? ArtInk.white : t.primary,
                                    shadows: onImage ? ArtInk.onArtShadows : null,
                                  ),
                                )
                              : FlagBadge(
                                  flag!,
                                  size: 40,
                                  // Saudi's disc is green on Sabily's
                                  // green ground and disappeared
                                  // without one.
                                  ring: onImage ? ArtInk.white : null,
                                  ringWidth: 1.5,
                                ),
                        ),
                        const Spacer(),
                        Text(
                          name,
                          style: AppType.bodyStrong.copyWith(
                            color: onImage ? ArtInk.white : t.primary,
                            shadows: onImage ? ArtInk.onArtShadows : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (price != null) ...[
                          const SizedBox(height: Gap.xs),
                          Text(
                            price!,
                            style: AppType.caption.copyWith(
                              color: onImage ? ArtInk.onArtMuted : t.inkMuted,
                              shadows: onImage ? ArtInk.onArtShadows : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

    return AppChipRow(
      // Side padding matches the list below so the first chip lines up with
      // the cards; 8 below is the template's.
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm + Gap.lg),
      children: [
        for (final region in <Region?>[null, ...state.regions])
          AppFilterChip(
            label: l10n.t('catalog.region.${region?.name ?? 'all'}'),
            selected: state.region == region,
            onTap: () => select(region),
          ),
      ],
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

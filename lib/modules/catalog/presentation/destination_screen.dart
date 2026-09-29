import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/country_names.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/commerce/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/i18n/country_flags.dart';
import '../../../core/ui/flag_glyph.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/pack_card.dart';
import '../domain/catalog.dart';
import '../domain/pack_filter.dart';
import 'catalog_controllers.dart';
import 'widgets.dart';

/// Packs available for one destination.
///
/// Structure, spacing, radii and type follow Figma `Pack Details - Sabily
/// (Mobile)` (node 63:53), read with `get_design_context`, not traced from a
/// PNG. Its teals (`rgba(0,77,64,0.95)`, `#015552`) resolve to `primary`
/// (ARCHITECTURE-MOBILE.md §2.2.2).
///
/// The duration/data filters are not in the frame. They sit between the
/// heading and the first card in the canvas's own 16px rhythm, built from the
/// template's chip (66:54).
class DestinationScreen extends ConsumerWidget {
  final String code;
  const DestinationScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final async = ref.watch(destinationProvider(code));

    return Scaffold(
      backgroundColor: t.surface,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => StateMessage(
          icon: Icons.cloud_off,
          title: l10n.t('error.generic'),
          actionLabel: l10n.t('common.close'),
          onAction: () => context.pop(),
        ),
        data: (destination) {
          if (destination == null) {
            return StateMessage(
              icon: Icons.help_outline,
              title: l10n.t('catalog.destinationMissing'),
              actionLabel: l10n.t('common.close'),
              onAction: () => context.pop(),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(destination: destination)),
              _Packs(packs: destination.packs, destinationCode: destination.code),
            ],
          );
        },
      ),
    );
  }
}

/// The dark task-focused header: back action, flag disc, name, country code and
/// the "from … / GB" pill. It suppresses the main navigation, as the frame does.
class _Header extends ConsumerWidget {
  final Destination destination;
  const _Header({required this.destination});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final s = ShopTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    final name = countryName(destination.code, l10n.language, fallback: destination.name);
    final perGb = destination.bestPricePerGigabyte;
    final cheapest = destination.cheapestPrice;
    final flag = countryFlagAsset(destination.code);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xl),
      // 63:54 also draws a 5px backdrop blur. The header scrolls away with the
      // content rather than floating over it, so nothing ever sits behind it
      // to blur, and the filter is left out rather than paid for.
      decoration: BoxDecoration(
        // Solid unless the brand's shop fill has somewhere to go: a gradient
        // between two equal colours does not rasterise like the solid fill.
        color: s.headerEnd == s.fill ? s.fill.withValues(alpha: 0.95) : null,
        gradient: s.headerEnd == s.fill
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [s.fill.withValues(alpha: 0.95), s.headerEnd.withValues(alpha: 0.95)],
              ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(Radii.card),
          bottomRight: Radius.circular(Radii.card),
        ),
        boxShadow: Shadows.field,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BackPill(tooltip: l10n.t('common.close'), onTap: () => context.pop()),
                Expanded(
                  child: Text(
                    name,
                    style: AppType.title.copyWith(color: s.onFill),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The same flag the Store row showed on the way in.
                if (flag != null)
                  FlagBadge(
                    flag,
                    size: 64,
                    ring: s.onFill.withValues(alpha: 0.30),
                    shadow: Shadows.card,
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.onFill,
                      shape: BoxShape.circle,
                      boxShadow: Shadows.card,
                    ),
                    child: Text(
                      destination.code,
                      style: AppType.heading.copyWith(color: t.primary),
                    ),
                  ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppType.hero.copyWith(color: s.onFill),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        l10n.t('catalog.countryCode', vars: {'code': destination.code}),
                        style: AppType.label.copyWith(
                          color: s.onFill.withValues(alpha: 0.80),
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      Wrap(
                        spacing: Gap.sm,
                        runSpacing: Gap.xs,
                        children: [
                          if (perGb != null && cheapest != null)
                            _Pill(
                              background: s.badge,
                              border: s.badgeBorder,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    Money(
                                      wireAmount: perGb.toStringAsFixed(2),
                                      currencyCode: cheapest.currencyCode,
                                      symbol: cheapest.symbol,
                                    ).format(l10n.language),
                                    style: AppType.labelStrong.copyWith(color: s.onBadge),
                                  ),
                                  const SizedBox(width: Gap.xs),
                                  Text(
                                    l10n.t('catalog.perGigabyte'),
                                    style: AppType.caption.copyWith(
                                      color: s.onBadge.withValues(alpha: 0.75),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _Pill(
                            border: s.onFill.withValues(alpha: 0.40),
                            radius: Radii.badge,
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            child: Text(
                              ref.watch(brandConfigProvider.select((b) => b.currency)),
                              style: AppType.caption.copyWith(
                                color: s.onFill.withValues(alpha: 0.90),
                                letterSpacing: 0.24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The header's two tags. 63:78 is a pill (12 x 2); 63:81 is a 6px-radius
/// bordered badge (9 x 3).
class _Pill extends StatelessWidget {
  final Widget child;
  final Color? background;
  final Color? border;
  final double radius;
  final EdgeInsetsGeometry padding;

  const _Pill({
    required this.child,
    this.background,
    this.border,
    this.radius = Radii.pill,
    this.padding = const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 2),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: child,
      );
}

/// 63:56 "Button - Go back": a fully rounded control, no fill, padding
/// 8/8/14/8 around a 16px arrow — a pill that shows itself as a ripple.
///
/// The frame's pill is 32 x 38, under the 48dp minimum touch target, so the
/// target is padded to 48 while the pill keeps its drawn size inside it.
class BackPill extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  /// The arrow's colour: `onPrimary` on the dark header, `primary` on a light one.
  final Color? color;

  const BackPill({super.key, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final ink = color ?? t.onPrimary;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(32, 38),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: ink,
      ),
      // The arrow glyph fills 16 of its 24 grid: drawn at 24 inside a 16 box.
      icon: SizedBox(
        width: 16,
        height: 16,
        child: OverflowBox(
          maxWidth: 24,
          maxHeight: 24,
          // Directional: mirrors automatically in Arabic.
          child: Icon(Icons.arrow_back, size: 24, color: ink),
        ),
      ),
    );
  }
}

/// The pack list, with duration and data filters over the packs already here.
///
/// The selection is this screen's own state: it means nothing on another
/// destination, and leaving the screen should forget it.
class _Packs extends ConsumerStatefulWidget {
  final List<Pack> packs;
  final String destinationCode;
  const _Packs({required this.packs, required this.destinationCode});

  @override
  ConsumerState<_Packs> createState() => _PacksState();
}

class _PacksState extends ConsumerState<_Packs> {
  Validity? _duration;
  DataAllowance? _data;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final s = ShopTokens.of(context);
    final durations = durationOptions(widget.packs);
    final amounts = dataOptions(widget.packs);
    final shown = filterPacks(widget.packs, duration: _duration, data: _data);
    // The destination's picture, not each pack's coverage: most packs on a
    // country's page span many regions and would all fall back to `world`.

    return SliverMainAxisGroup(
      slivers: [
        // 63:83: 32 above, 16 between blocks, the heading with 8 of its own.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xl),
          sliver: SliverToBoxAdapter(
            child: Text(
              l10n.t('catalog.availablePacks'),
              // A large title: the one size of text the shop hue may colour.
              style: AppType.title.copyWith(color: s.display),
            ),
          ),
        ),
        // A dimension with one value has nothing to choose between.
        if (durations.length > 1)
          SliverToBoxAdapter(
            child: _FilterRow(
              label: l10n.t('catalog.validity'),
              allLabel: l10n.t('catalog.region.all'),
              allSelected: _duration == null,
              onAll: () => setState(() => _duration = null),
              options: [
                for (final v in durations)
                  (packValidityLabel(l10n, v), sameDuration(v, _duration), () => setState(() => _duration = v)),
              ],
            ),
          ),
        if (amounts.length > 1)
          SliverToBoxAdapter(
            child: _FilterRow(
              label: l10n.t('catalog.data'),
              allLabel: l10n.t('catalog.region.all'),
              allSelected: _data == null,
              onAll: () => setState(() => _data = null),
              options: [
                for (final d in amounts)
                  (packDataLabel(l10n, d), sameData(d, _data), () => setState(() => _data = d)),
              ],
            ),
          ),
        // The filters close with the same 24 the heading does, so the first
        // card sits the same distance below whatever precedes it.
        if (durations.length > 1 || amounts.length > 1)
          const SliverToBoxAdapter(child: SizedBox(height: Gap.sm)),
        if (shown.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, 48),
              child: StateMessage(
                icon: Icons.filter_alt_off_outlined,
                title: l10n.t('catalog.filter.noMatch'),
                actionLabel: l10n.t('catalog.filter.clear'),
                onAction: () => setState(() {
                  _duration = null;
                  _data = null;
                }),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 48),
            sliver: SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
              itemBuilder: (context, i) => _PackIdentityCard(
                key: ValueKey(shown[i].id),
                pack: shown[i],
                destinationCode: widget.destinationCode,
              ),
            ),
          ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final String allLabel;
  final List<(String, bool, VoidCallback)> options;
  final bool allSelected;
  final VoidCallback onAll;

  const _FilterRow({
    required this.label,
    required this.allLabel,
    required this.options,
    required this.allSelected,
    required this.onAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // An eyebrow, not body text: VALIDITY and DATA are headings for
          // the chip rows under them, the same as ALL DESTINATIONS is for
          // the list on Store. As sentence-case 14px they read as a label
          // belonging to the first chip.
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
            child: AppEyebrow(label),
          ),
          AppChipRow(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            children: [
              AppFilterChip(label: allLabel, selected: allSelected, onTap: onAll),
              for (final (text, selected, onTap) in options)
                AppFilterChip(label: text, selected: selected, onTap: onTap),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Available-Packs card: the destination's real outline, the pack's
/// facts, the brand's button.
///
/// An adapter rather than a widget of its own — [PackCard] knows nothing
/// about `Pack`, so the same card can be fed by a different catalogue later.
class _PackIdentityCard extends ConsumerWidget {
  final Pack pack;
  final String destinationCode;

  const _PackIdentityCard({super.key, required this.pack, required this.destinationCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final language = ref.watch(languageProvider);
    // The pack's OWN coverage, not the destination's: this is what makes a
    // Europe pack draw the zone treatment while a France pack draws France.
    final covered = pack.countryCodes;
    final zone = covered.length > 1;
    final price = pack.price;

    return PackCard(
      destinationCode: destinationCode,
      coveredCodes: covered,
      title: pack.name,
      dataLabel: packDataLabel(l10n, pack.data),
      validityLabel: l10n.t('catalog.validity'),
      validityValue: packValidityLabel(l10n, pack.validity),
      coverageLabel: l10n.t('catalog.coverage'),
      coverageValue: zone
          ? l10n.t('catalog.countryCount', vars: {'count': '${covered.length}'})
          : countryName(destinationCode, language, fallback: destinationCode),
      price: price?.format(language),
      dataCellLabel: l10n.t('catalog.data'),
      buyLabel: price == null
          ? l10n.t('catalog.buyThisPack')
          : l10n.t('catalog.buyFor', vars: {'amount': price.format(language)}),
      tagLabel: l10n.t(zone ? 'catalog.tag.zone' : 'catalog.tag.country'),
      regionalLabel: zone ? l10n.t('catalog.regional') : null,
      onTap: () => context.pushNamed(
        'pack',
        pathParameters: {'code': destinationCode, 'id': '${pack.id}'},
      ),
      onBuy: () => buyPack(context, ref, pack, destinationCode: destinationCode),
    );
  }
}

/// Starts checkout for [pack]. Shared by the pack card and the detail screen.
///
/// Catalogue must not import checkout — rule L2. It asks the registry, which
/// lives in core, whether checkout is available, and says so plainly when it
/// is not. This is the same guard shape the wallet flag uses.
void buyPack(BuildContext context, WidgetRef ref, Pack pack, {String? destinationCode}) {
  final registry = ref.read(moduleRegistryProvider);
  final l10n = ref.read(l10nProvider);

  // A pack priced only in another currency has no price in THIS brand's
  // currency, and there is nothing honest to charge. The card already hides
  // the amount in that case; this refuses the purchase rather than sending a
  // null or a zero to the payment endpoint.
  final price = pack.price;
  if (price == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('catalog.destinationMissing'))),
    );
    return;
  }

  if (!registry.isActive('checkout')) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('common.comingSoon'))),
    );
    return;
  }
  // The EXACT decimal travels with the request, as the string the server
  // sent. Nothing here parses it to a number — that is the defect this whole
  // module exists to not reintroduce.
  context.pushNamed(
    'checkout',
    extra: PurchaseRequest(
      packId: pack.id,
      packName: pack.name,
      summary: '${packDataLabel(l10n, pack.data)} · ${packValidityLabel(l10n, pack.validity)}',
      amount: price,
      destinationCode: destinationCode,
    ),
  );
}

/// "10 GB" / "10 غيغابايت" — the unit is a dictionary key, never a literal.
String packDataLabel(L10n l10n, DataAllowance data) {
  final size = data.size;
  return switch (size.unit) {
    DataUnit.unlimited => l10n.t('catalog.unlimited'),
    DataUnit.none => size.amount,
    DataUnit.gigabyte => '${size.amount} ${l10n.t('catalog.unit.gigabyte')}',
    DataUnit.megabyte => '${size.amount} ${l10n.t('catalog.unit.megabyte')}',
    DataUnit.kilobyte => '${size.amount} ${l10n.t('catalog.unit.kilobyte')}',
  };
}

/// "7 days" — pluralised properly. The live app printed the API's raw
/// duration and unit and produced "1 days", which is visible in the September
/// mockups because they are screenshots of it.
String packValidityLabel(L10n l10n, Validity v) {
  final n = v.amount!;
  final key = switch (v.kind) {
    ValidityUnit.month => n == 1 ? 'catalog.monthOne' : 'catalog.monthMany',
    ValidityUnit.year => n == 1 ? 'catalog.yearOne' : 'catalog.yearMany',
    ValidityUnit.day => n == 1 ? 'catalog.dayOne' : 'catalog.dayMany',
  };
  return l10n.t(key, vars: {'count': '$n'});
}

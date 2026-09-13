import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/commerce/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../domain/catalog.dart';
import '../domain/pack_filter.dart';
import 'catalog_controllers.dart';
import 'widgets.dart';

/// Packs available for one destination.
///
/// Structure, spacing and radii follow Figma `Pack Details - Sabily (Mobile)`
/// (node 63:53), read as computed values rather than traced from a PNG. Colours
/// come from the brand tokens: that frame paints its header `#004d40`, which is
/// the August batch's primary, while its cards use `#003c3a`. ARCHITECTURE-
/// MOBILE.md §2.2 already arbitrated that inconsistency in favour of `#003c3a`,
/// so the header uses the `primary` token and the frame's outlier is not
/// reintroduced.
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
              _Packs(packs: destination.packs),
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
    final l10n = ref.watch(l10nProvider);
    final perGb = destination.bestPricePerGigabyte;
    final cheapest = destination.cheapestPrice;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xl),
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(Radii.card),
          bottomRight: Radius.circular(Radii.card),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  // Directional: mirrors automatically in Arabic.
                  icon: Icon(Icons.arrow_back, color: t.onPrimary),
                  tooltip: l10n.t('common.close'),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    destination.name,
                    style: AppType.title.copyWith(color: t.onPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.onPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.onPrimary.withValues(alpha: 0.30), width: 2),
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
                        destination.name,
                        style: AppType.hero.copyWith(color: t.onPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        l10n.t('catalog.countryCode', vars: {'code': destination.code}),
                        style: AppType.label.copyWith(
                          color: t.onPrimary.withValues(alpha: 0.80),
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
                              background: t.accent,
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
                                    style: AppType.labelStrong.copyWith(color: t.primary),
                                  ),
                                  const SizedBox(width: Gap.xs),
                                  Text(
                                    l10n.t('catalog.perGigabyte'),
                                    style: AppType.caption.copyWith(color: t.primary),
                                  ),
                                ],
                              ),
                            ),
                          _Pill(
                            border: t.onPrimary.withValues(alpha: 0.40),
                            child: Text(
                              ref.watch(brandConfigProvider.select((b) => b.currency)),
                              style: AppType.captionStrong
                                  .copyWith(color: t.onPrimary.withValues(alpha: 0.90)),
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

class _Pill extends StatelessWidget {
  final Widget child;
  final Color? background;
  final Color? border;

  const _Pill({required this.child, this.background, this.border});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: child,
      );
}

/// The pack list, with duration and data filters over the packs already here.
///
/// The selection is this screen's own state: it means nothing on another
/// destination, and leaving the screen should forget it.
class _Packs extends ConsumerStatefulWidget {
  final List<Pack> packs;
  const _Packs({required this.packs});

  @override
  ConsumerState<_Packs> createState() => _PacksState();
}

class _PacksState extends ConsumerState<_Packs> {
  Validity? _duration;
  DataAllowance? _data;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final durations = durationOptions(widget.packs);
    final amounts = dataOptions(widget.packs);
    final shown = filterPacks(widget.packs, duration: _duration, data: _data);

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.lg),
          sliver: SliverToBoxAdapter(
            child: Text(
              l10n.t('catalog.availablePacks'),
              style: AppType.title.copyWith(color: t.primary),
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
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 48),
            sliver: SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
              itemBuilder: (context, i) => _PackCard(key: ValueKey(shown[i].id), pack: shown[i]),
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
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
            child: Text(label, style: AppType.label.copyWith(color: t.inkMuted)),
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

class _PackCard extends ConsumerWidget {
  final Pack pack;
  const _PackCard({super.key, required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    final price = pack.price;

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.control),
        boxShadow: Shadows.field,
        border: Border.all(color: t.fieldBorder),
      ),
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PackMedia(pack: pack, popularLabel: l10n.t('catalog.popular')),
          const SizedBox(height: Gap.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: Gap.lg),
                  child: Text(pack.name, style: AppType.heading.copyWith(color: t.primary)),
                ),
              ),
              if (price != null) PricePill(price: price),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              children: [
                SpecItem(
                  icon: Icons.data_usage,
                  value: packDataLabel(l10n, pack.data),
                  label: l10n.t('catalog.data'),
                ),
                const SizedBox(width: Gap.xl),
                if (pack.validity.isKnown)
                  SpecItem(
                    icon: Icons.schedule,
                    value: packValidityLabel(l10n, pack.validity),
                    label: l10n.t('catalog.validity'),
                  ),
              ],
            ),
          ),
          Divider(color: t.hairline, height: 1),
          if (pack.description != null) ...[
            const SizedBox(height: Gap.md),
            Text(
              pack.description!,
              style: AppType.label.copyWith(color: t.inkMuted, letterSpacing: 0),
            ),
          ],
          const SizedBox(height: Gap.lg),
          // The one place the brand's call-to-action pair belongs: money.
          AppButton(
            label: l10n.t('catalog.buyThisPack'),
            tone: AppButtonTone.cta,
            onPressed: () => _buy(context, ref),
          ),
        ],
      ),
    );
  }

  /// Catalogue must not import checkout — rule L2. It asks the registry, which
  /// lives in core, whether checkout is available, and says so plainly when it
  /// is not. This is the same guard shape the wallet flag uses.
  void _buy(BuildContext context, WidgetRef ref) {
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
      ),
    );
  }
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

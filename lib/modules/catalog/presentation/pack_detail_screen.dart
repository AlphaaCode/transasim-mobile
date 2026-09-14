/// One pack, in full. From the White-Label Details Template (Figma 66:194),
/// read with `get_design_context`, then adapted to the data packs really carry.
///
/// Kept from the template: the header, the hero, the title, the price, the
/// stat cards, one content card, a buy button fixed to the foot of the screen.
///
/// Dropped, because no such data exists on a pack (live API and backend code
/// both checked): the star rating, the "High-speed 4G/5G" subtitle, the Speed
/// stat (network generation is a pending backend request), and the marketing
/// description with its feature list. Nothing is invented to fill them.
///
/// The template's description card holds coverage instead: the countries the
/// pack actually works in, which is real data and what a buyer needs to know,
/// most of all for a multi-country pack like Best World (178 countries).
///
/// The template's teal (#114c49) resolves to `primary` (§2.2.2), its generic
/// fonts to the socle's three families, its greys to the ink tokens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../domain/catalog.dart';
import 'catalog_controllers.dart';
import 'destination_screen.dart';
import 'widgets.dart';

class PackDetailScreen extends ConsumerWidget {
  final String destinationCode;
  final int packId;

  const PackDetailScreen({super.key, required this.destinationCode, required this.packId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final async = ref.watch(destinationProvider(destinationCode));

    final Pack? pack = async.value?.packs.where((p) => p.id == packId).firstOrNull;

    return Scaffold(
      backgroundColor: t.surface,
      bottomNavigationBar: pack == null ? null : _BuyBar(pack: pack),
      body: Column(
        children: [
          // 66:195: back pill and title on the page ground.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.lg, Gap.xs),
              child: Row(
                children: [
                  BackPill(
                    tooltip: l10n.t('common.close'),
                    color: t.primary,
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      l10n.t('catalog.packDetails'),
                      style: AppType.heading.copyWith(color: t.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (async) {
              AsyncValue(isLoading: true, value: null) =>
                const Center(child: CircularProgressIndicator()),
              _ when pack == null => StateMessage(
                  icon: Icons.help_outline,
                  title: l10n.t('catalog.destinationMissing'),
                  actionLabel: l10n.t('common.close'),
                  onAction: () => context.pop(),
                ),
              _ => _Details(pack: pack, destinationCode: destinationCode),
            },
          ),
        ],
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  final Pack pack;
  final String destinationCode;
  const _Details({required this.pack, required this.destinationCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final price = pack.price;
    final language = ref.watch(languageProvider);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 66:210: 276 visible, bottom corners 24, lifted. The photo is the same
        // regional stand-in the pack card uses, under the same treatment.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.card)),
            boxShadow: Shadows.card,
          ),
          child: PackMedia(
            pack: pack,
            popularLabel: l10n.t('catalog.popular'),
            fallbackAsset: ref.watch(destinationImageProvider(destinationCode)),
            height: 276,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.card)),
          ),
        ),
        // 66:220: 16 sides, 24 top and bottom, 24 between blocks.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                pack.name,
                style: AppType.display.copyWith(color: t.ink, letterSpacing: -0.64),
              ),
              if (price != null) ...[
                // 66:221 gap 12 + 66:233 top margin 8.
                const SizedBox(height: Gap.md + Gap.sm),
                Text(
                  price.format(language),
                  style: AppType.display.copyWith(color: t.primary, letterSpacing: -0.64),
                ),
              ],
              const SizedBox(height: Gap.xl + Gap.lg),
              // 66:238: two columns, 12 apart. Data and Validity only.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.data_usage,
                        disc: t.accent,
                        glyph: t.primary,
                        label: l10n.t('catalog.data'),
                        value: packDataLabel(l10n, pack.data),
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.schedule,
                        disc: t.primary,
                        glyph: t.onPrimary,
                        label: l10n.t('catalog.validity'),
                        value: pack.validity.isKnown ? packValidityLabel(l10n, pack.validity) : '—',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xl + Gap.lg),
              _Coverage(codes: pack.countryCodes, destinationCode: destinationCode),
            ],
          ),
        ),
      ],
    );
  }
}

/// 66:239: a white tile, 8 radius, 17 padding, a 48 disc over a 12/16 label
/// and a 20/28 value.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color disc;
  final Color glyph;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.disc,
    required this.glyph,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: t.cardBorder),
        boxShadow: Shadows.badge,
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: glyph),
          ),
          const SizedBox(height: Gap.md),
          Text(label, style: AppType.chip.copyWith(color: t.inkMuted), textAlign: TextAlign.center),
          Text(value, style: AppType.cardTitle.copyWith(color: t.ink), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// The template's description card, holding the countries the pack covers.
/// The destination the user came from leads; the rest follow alphabetically.
class _Coverage extends ConsumerStatefulWidget {
  final List<String> codes;
  final String destinationCode;
  const _Coverage({required this.codes, required this.destinationCode});

  @override
  ConsumerState<_Coverage> createState() => _CoverageState();
}

class _CoverageState extends ConsumerState<_Coverage> {
  /// A list this long stays readable; past it, the rest is one tap away.
  static const _collapsedCount = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final names = ref.watch(countryNamesProvider).value ?? const <String, String>{};

    String nameOf(String code) => names[code] ?? code;
    final here = widget.destinationCode.toUpperCase();
    final sorted = [...widget.codes.map((c) => c.toUpperCase()).toSet()]
      ..sort((a, b) {
        if (a == here) return -1;
        if (b == here) return 1;
        return nameOf(a).compareTo(nameOf(b));
      });
    final count = sorted.length;
    final visible = _expanded ? sorted : sorted.take(_collapsedCount).toList();

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: t.cardBorder),
        boxShadow: Shadows.badge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 20, color: t.primary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  l10n.t('catalog.coverage'),
                  style: AppType.cardTitle.copyWith(color: t.ink),
                ),
              ),
              Text(
                l10n.t(count == 1 ? 'catalog.countryOne' : 'catalog.countryMany',
                    vars: {'count': '$count'}),
                style: AppType.label.copyWith(color: t.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          for (final code in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 20, color: t.primary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(nameOf(code), style: AppType.body.copyWith(color: t.inkMuted)),
                  ),
                ],
              ),
            ),
          if (count > _collapsedCount)
            AppLinkButton(
              label: _expanded
                  ? l10n.t('catalog.coverageShowLess')
                  : l10n.t('catalog.coverageShowAll', vars: {'count': '$count'}),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

/// 66:202: fixed to the foot, a hairline above, a soft upward lift.
class _BuyBar extends ConsumerWidget {
  final Pack pack;
  const _BuyBar({required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final price = pack.price;

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.hairline)),
        boxShadow: Shadows.bottomBar,
      ),
      padding: const EdgeInsets.fromLTRB(Gap.lg, 17, Gap.lg, Gap.lg),
      child: SafeArea(
        top: false,
        child: AppButton(
          icon: Icons.shopping_cart_outlined,
          label: price == null
              ? l10n.t('catalog.buyThisPack')
              : l10n.t('catalog.buyFor', vars: {'amount': price.format(ref.watch(languageProvider))}),
          onPressed: price == null ? null : () => buyPack(context, ref, pack),
        ),
      ),
    );
  }
}

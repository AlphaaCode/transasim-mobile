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
import '../../../core/i18n/country_flags.dart';
import '../../../core/i18n/country_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/flag_glyph.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
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
      bottomNavigationBar:
          pack == null ? null : _BuyBar(pack: pack, destinationCode: destinationCode),
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
              _ => _Details(
                  pack: pack,
                  destinationCode: destinationCode,
                  destinationName: async.value?.name,
                ),
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

  /// The destination's real name, threaded down from [PackDetailScreen] so
  /// the identity card can show it as a subtitle without re-fetching or
  /// falling back to the bare ISO code.
  final String? destinationName;

  const _Details({required this.pack, required this.destinationCode, this.destinationName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final price = pack.price;
    final language = ref.watch(languageProvider);
    final flag = countryFlagAsset(destinationCode);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // The pack's identity: its destination's real flag (country_flags.dart
        // — the same lookup DestinationTile reads) and name, replacing the
        // regional stand-in photo the pack CARD still shows in a list (where
        // one picture has to stand for a whole region). A single pack's own
        // page can afford to be specific instead.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.accent, t.surface],
              ),
              borderRadius: BorderRadius.circular(Radii.card),
              boxShadow: Shadows.card,
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (flag != null)
                    FlagBadge(flag, size: 56, shadow: Shadows.field)
                  else
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                        boxShadow: Shadows.field,
                      ),
                      child: Text(
                        destinationCode.toUpperCase(),
                        style: AppType.labelStrong.copyWith(color: t.primary),
                      ),
                    ),
                  const SizedBox(height: Gap.md),
                  Text(
                    pack.name,
                    style: AppType.display.copyWith(color: t.ink, letterSpacing: -0.64),
                  ),
                  if (destinationName != null) ...[
                    const SizedBox(height: Gap.xs),
                    Text(destinationName!, style: AppType.body.copyWith(color: t.inkMuted)),
                  ],
                  if (price != null) ...[
                    // 66:221 gap 12 + 66:233 top margin 8.
                    const SizedBox(height: Gap.md + Gap.sm),
                    Text(
                      price.format(language),
                      style: AppType.display.copyWith(color: t.primary, letterSpacing: -0.64),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // 66:220: 16 sides, 24 top and bottom, 24 between blocks.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const _GoodToKnow(),
              const SizedBox(height: Gap.xl + Gap.lg),
              _Coverage(codes: pack.countryCodes, destinationCode: destinationCode),
            ],
          ),
        ),
      ],
    );
  }
}

/// What every eSIM in this catalogue does, said once on the page where
/// someone is deciding whether to buy one.
///
/// The three lines are properties of the product, not of a pack, so they are
/// dictionary entries rather than anything the backend sends: no pack in the
/// live catalogue carries per-pack notes today, and inventing a field for
/// copy that never varies would be a schema change for nothing.
class _GoodToKnow extends ConsumerWidget {
  const _GoodToKnow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(Gap.lg + Gap.xs),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: t.cardBorder),
        boxShadow: Shadows.badge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppEyebrow(l10n.t('catalog.goodToKnow')),
          const SizedBox(height: Gap.md),
          for (final key in const [
            'catalog.goodToKnow.dataOnly',
            'catalog.goodToKnow.autoActivates',
            'catalog.goodToKnow.alongside',
          ]) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                    child: Icon(Icons.check, size: 13, color: t.primary),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(l10n.t(key), style: AppType.prose.copyWith(color: t.inkMuted)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
        return compareCountryNames(nameOf(a), nameOf(b));
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
                  // Same flag, same fallback as the store list's
                  // DestinationTile (`widgets.dart` / `country_flags.dart`) — a
                  // covered country reads better by its flag than by a generic
                  // checkmark, and the checkmark is exactly what's still there
                  // when a code can't resolve to one.
                  _coverageGlyph(code, t.primary),
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

/// A covered country's leading glyph: its flag, or the checkmark this row
/// drew before flags existed — kept as the fallback for when
/// [countryFlagAsset] can't resolve [code].
Widget _coverageGlyph(String code, Color primary) {
  final flag = countryFlagAsset(code);
  return flag != null
      ? FlagBadge(flag, size: 20)
      : Icon(Icons.check_circle_outline, size: 20, color: primary);
}

/// 66:202: fixed to the foot, a hairline above, a soft upward lift.
class _BuyBar extends ConsumerWidget {
  final Pack pack;
  final String destinationCode;
  const _BuyBar({required this.pack, required this.destinationCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final price = pack.price;

    return Container(
      // Page ground, no seam: the button's own shadow does the lifting.
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.lg),
      child: SafeArea(
        top: false,
        child: AppButton(
          icon: Icons.shopping_bag_outlined,
          tone: AppButtonTone.cta,
          label: price == null
              ? l10n.t('catalog.buyThisPack')
              : l10n.t('catalog.buyFor', vars: {'amount': price.format(ref.watch(languageProvider))}),
          onPressed: price == null
              ? null
              : () => buyPack(context, ref, pack, destinationCode: destinationCode),
        ),
      ),
    );
  }
}

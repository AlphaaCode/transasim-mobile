/// A pack, as the Available-Packs screen draws it: the destination's real
/// outline on a topographic ground, then the pack's own facts underneath.
///
/// The same split as [DestinationCard] and for the same reason — the art
/// belongs to the DESTINATION (its outline, its colour), everything else to
/// the brand ([AppTokens]). What differs is fidelity: Store settles for a
/// colour swell, this screen draws the country.
///
/// A pack covering more than one country has no single shape to draw, so it
/// gets the zone treatment instead: the ground, a scatter of the flags it
/// covers, and a count for the rest.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_card.dart';
import '../art/pack_art.dart';

class PackCard extends StatelessWidget {
  /// The destination this pack was opened from — the shape to draw.
  final String destinationCode;

  /// Every country the pack covers. More than one makes it a zone card.
  final List<String> coveredCodes;

  final String title;
  final String dataLabel;
  final String validityLabel;
  final String validityValue;
  final String coverageLabel;
  final String coverageValue;
  final String? price;
  /// "Data" — the stat cell's own label, beside [dataLabel]'s value.
  final String dataCellLabel;

  /// The full-width action: "Buy this pack - 6,00 EUR".
  final String buyLabel;

  /// "COUNTRY" / "ZONE MAP", above the art.
  final String tagLabel;

  /// "Regional", top-right, on a zone card only.
  final String? regionalLabel;

  /// Opens the pack's detail screen.
  final VoidCallback onTap;

  /// The CTA's own action — the FAST PATH straight to checkout, deliberately
  /// not the detail screen. The card has always had two doors and the
  /// redesign keeps both: the body explains the pack, the button buys it.
  final VoidCallback onBuy;

  const PackCard({
    super.key,
    required this.destinationCode,
    required this.coveredCodes,
    required this.title,
    required this.dataLabel,
    required this.validityLabel,
    required this.validityValue,
    required this.coverageLabel,
    required this.coverageValue,
    required this.dataCellLabel,
    required this.buyLabel,
    required this.tagLabel,
    required this.onTap,
    required this.onBuy,
    this.price,
    this.regionalLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final l10nRadius = BorderRadius.circular(Radii.card);

    return AppPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: l10nRadius,
          color: t.card,
          boxShadow: Shadows.float(t.primary),
        ),
        child: ClipRRect(
          borderRadius: l10nRadius,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Tag(label: tagLabel),
                    const Spacer(),
                    if (regionalLabel != null) _RegionalPill(label: regionalLabel!),
                  ],
                ),
                const SizedBox(height: Gap.md),
                // The price rides on the art rather than competing with the
                // stats below it: it is the one number a scanning eye looks
                // for, and it reads fastest against the card's own picture.
                Stack(
                  children: [
                    _Art(destinationCode: destinationCode, coveredCodes: coveredCodes),
                    if (price != null)
                      Positioned(
                        top: Gap.sm,
                        right: Gap.sm,
                        child: _PriceBadge(price: price!),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  title,
                  style: AppType.cardTitle.copyWith(color: t.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Gap.md),
                // The detail screen's own stat cells, ported rather than
                // reinvented: one visual language for "how much data, for how
                // long", whichever screen it is read on.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _StatCell(
                          icon: Icons.data_usage,
                          disc: t.accent,
                          glyph: t.primary,
                          label: dataCellLabel,
                          value: dataLabel,
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: _StatCell(
                          icon: Icons.schedule,
                          disc: t.primary,
                          glyph: t.onPrimary,
                          label: validityLabel,
                          value: validityValue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                _SpecRow(label: coverageLabel, value: coverageValue),
                const SizedBox(height: Gap.lg),
                // Full width, and the buy fast path — not the detail screen.
                AppButton(
                  icon: Icons.shopping_bag_outlined,
                  tone: AppButtonTone.cta,
                  label: buyLabel,
                  onPressed: onBuy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The price, over the art.
class _PriceBadge extends StatelessWidget {
  final String price;

  const _PriceBadge({required this.price});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 1),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: Shadows.badge,
      ),
      child: Text(
        price,
        style: AppType.bodyStrong.copyWith(color: ShopTokens.of(context).display),
      ),
    );
  }
}

/// The pack-detail screen's stat cell, ported here unchanged in look: a glyph
/// on a coloured disc over a label and a value.
class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color disc;
  final Color glyph;
  final String label;
  final String value;

  const _StatCell({
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
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: t.cardBorder),
        boxShadow: Shadows.badge,
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: glyph),
          ),
          const SizedBox(height: Gap.sm),
          Text(label, style: AppType.chip.copyWith(color: t.inkMuted), textAlign: TextAlign.center),
          Text(
            value,
            style: AppType.cardTitle.copyWith(color: t.ink),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The art: the pack-art renderer, in the card's 16:9 window.
class _Art extends StatelessWidget {
  final String destinationCode;
  final List<String> coveredCodes;

  const _Art({required this.destinationCode, required this.coveredCodes});

  static const double _height = 132;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.tile),
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: PackArt(
          // The PACK's coverage, not the destination's: this is what makes a
          // Europe pack draw the zone and a France pack draw France.
          codes: coveredCodes.isEmpty ? <String>[destinationCode] : coveredCodes,
          current: destinationCode,
          primary: t.primary,
          accent: t.accent,
          cta: t.cta,
        ),
      ),
    );
  }
}

/// "COUNTRY" / "ZONE MAP", above the art.
class _Tag extends StatelessWidget {
  final String label;

  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: t.chipSurface,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: AppType.caption.copyWith(color: t.inkMuted, letterSpacing: 0.6),
      ),
    );
  }
}

/// "Regional", top-right, on a zone card only.
class _RegionalPill extends StatelessWidget {
  final String label;

  const _RegionalPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(label, style: AppType.captionStrong.copyWith(color: t.primary)),
    );
  }
}

/// A label on the left, its value on the right. Coverage only now — data and
/// validity moved to the stat cells above.
class _SpecRow extends StatelessWidget {
  final String label;
  final String value;

  const _SpecRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: [
        Text(label, style: AppType.body.copyWith(color: t.inkMuted)),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppType.bodyStrong.copyWith(color: t.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

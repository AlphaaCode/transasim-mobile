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
import 'package:flutter_svg/flutter_svg.dart';

import '../i18n/country_flags.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'country_shape.dart';
import 'flag_glyph.dart';

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
  final String actionLabel;

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
    required this.actionLabel,
    required this.tagLabel,
    required this.onTap,
    required this.onBuy,
    this.price,
    this.regionalLabel,
  });

  bool get _zone => coveredCodes.length > 1;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final l10nRadius = BorderRadius.circular(Radii.card);
    final value = countryColorValue(destinationCode);
    final tint = value == null ? t.primary : Color(value);

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
                _Art(
                  destinationCode: destinationCode,
                  coveredCodes: coveredCodes,
                  tint: tint,
                  zone: _zone,
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  title,
                  style: AppType.cardTitle.copyWith(color: t.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Gap.xs),
                Text(dataLabel, style: AppType.display.copyWith(color: t.ink)),
                const SizedBox(height: Gap.md),
                _SpecRow(label: validityLabel, value: validityValue),
                const SizedBox(height: Gap.sm),
                _SpecRow(label: coverageLabel, value: coverageValue),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    if (price != null)
                      Text(
                        price!,
                        style: AppType.title.copyWith(color: ShopTokens.of(context).display),
                      ),
                    const Spacer(),
                    _CtaButton(label: actionLabel, onTap: onBuy),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The art: topographic ground, then either the country or the zone.
class _Art extends StatelessWidget {
  final String destinationCode;
  final List<String> coveredCodes;
  final Color tint;
  final bool zone;

  const _Art({
    required this.destinationCode,
    required this.coveredCodes,
    required this.tint,
    required this.zone,
  });

  static const double _height = 132;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.tile);
    final alpha2 = countryFlagAsset(destinationCode);
    final flagMap = countryFlagMapAsset(destinationCode);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: Stack(
          children: [
            // The cream/mint ground, from the brand's own accent and surface
            // so it is mint for Sabily and cyan for eSimple without a switch.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.alphaBlend(t.accent.withValues(alpha: 0.55), t.card),
                      t.surface,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: TopographicWash(line: t.primary.withValues(alpha: 0.07)),
            ),
            if (zone)
              Positioned.fill(child: _ZoneMarkers(codes: coveredCodes))
            // The country's own flag-map, centred on the brand ground: its
            // outline filled with its own flag. 90 destinations have one.
            else if (flagMap != null)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                  child: SvgPicture.asset(flagMap, fit: BoxFit.contain),
                ),
              )
            // The rest keep the Natural Earth silhouette, which covers 175
            // countries at a fraction of the weight.
            else
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: CountryOutline(
                    alpha2: _alpha2Of(destinationCode) ?? '',
                    color: tint.withValues(alpha: 0.78),
                  ),
                ),
              ),
            // The location pin, top-left of the art area.
            Positioned(
              left: Gap.sm,
              top: Gap.sm,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.card,
                  shape: BoxShape.circle,
                  boxShadow: Shadows.badge,
                ),
                child: Icon(Icons.place_outlined, size: 15, color: t.primary),
              ),
            ),
            // A destination with no outline still gets its flag, so the art
            // never renders as an empty rectangle.
            if (!zone &&
                flagMap == null &&
                !hasCountryShape(_alpha2Of(destinationCode) ?? '') &&
                alpha2 != null)
              Positioned(
                right: Gap.lg,
                top: 0,
                bottom: 0,
                child: Center(child: FlagBadge(alpha2, size: 56, shadow: Shadows.badge)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The zone card's art: the flags it covers, scattered, plus a count.
class _ZoneMarkers extends StatelessWidget {
  final List<String> codes;

  const _ZoneMarkers({required this.codes});

  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final assets = <String>[];
    for (final c in codes) {
      final a = countryFlagAsset(c);
      if (a != null) assets.add(a);
      if (assets.length == _shown) break;
    }
    final rest = codes.length - assets.length;

    // Fixed offsets rather than random: a card that rearranges itself on
    // every rebuild looks broken, and a seeded shuffle would be one more
    // thing to explain for no visible gain.
    const spots = <Alignment>[
      Alignment(-0.45, -0.35),
      Alignment(0.05, 0.25),
      Alignment(0.5, -0.5),
      Alignment(-0.1, -0.7),
      Alignment(0.62, 0.45),
    ];

    return Stack(
      children: [
        for (var i = 0; i < assets.length; i++)
          Align(
            alignment: spots[i % spots.length],
            child: FlagBadge(assets[i], size: 30, shadow: Shadows.badge),
          ),
        if (rest > 0)
          Positioned(
            right: Gap.sm,
            bottom: Gap.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
              decoration: BoxDecoration(
                color: t.primary,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '+$rest',
                style: AppType.captionStrong.copyWith(color: t.onPrimary),
              ),
            ),
          ),
      ],
    );
  }
}

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

class _CtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CtaButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // ShopTokens.buy, NOT AppTokens.cta. This button spends money, so it
    // follows the same rule as every other buy action in the app — which for
    // eSimple means navy, never one of the cyan fills the shop uses for its
    // surfaces. The Store card's button keeps the generic accent because it
    // only navigates; this one commits.
    final s = ShopTokens.of(context);
    const shape = StadiumBorder();
    return Material(
      color: s.buy,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.sm + 2),
          child: Text(label, style: AppType.labelStrong.copyWith(color: s.onBuy)),
        ),
      ),
    );
  }
}

/// The catalogue speaks alpha-3; the shape table is keyed alpha-2.
String? _alpha2Of(String code) {
  final asset = countryFlagAsset(code);
  if (asset == null) return null;
  // 'assets/flags/at.svg' -> 'at'
  final name = asset.split('/').last;
  return name.substring(0, name.length - 4);
}

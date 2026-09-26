/// A destination's identity card: its own colour and flag as a backdrop,
/// everything else in the brand's colours.
///
/// The split is the whole point of this widget, and it is the thing to
/// preserve if it is ever rewritten:
///
///   * the BACKDROP belongs to the destination — Austria reads red, Italy
///     green, Saudi Arabia green — derived from the bundled flag by
///     `countryColorValue`, identical in every white-label app;
///   * everything drawn ON it — the name, the price, the button, the pills —
///     comes from [AppTokens], so a brand never configures a country and a
///     country never configures a brand.
///
/// That is why there is no per-brand-per-country map anywhere: the only
/// per-country datum is generated from `assets/flags/`, which is itself
/// generated from the catalogue's own codes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../i18n/country_flags.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'flag_glyph.dart';

/// The card's art: the brand's ground, then the destination on top of it.
///
/// Three layers, in this order, and the order is the design:
///
///   1. the BRAND's background image (`mobile.cardBackground`, from its own
///      `assets/` folder) — per brand, never hardcoded, absent for a brand
///      that has not supplied one;
///   2. the DESTINATION's flag-map, centred — its outline filled with its own
///      flag, for the 90 countries that ship one;
///   3. failing that, the colour wash and soft swell that every other
///      destination still gets.
///
/// A country never configures a brand and a brand never configures a country:
/// layer 1 comes from `brand.json`, layer 2 from the curated allow-list, and
/// neither knows about the other.
class CountryBackdrop extends StatelessWidget {
  final String? flagAsset;

  /// The destination's flag-map, or `null` when it has none.
  final String? flagMapAsset;

  /// The brand's own background image, or `null` when it ships none.
  final String? backgroundAsset;

  /// The destination's identity colour.
  final Color tint;

  /// Whether to float the flag artwork behind the content as a watermark.
  ///
  /// REVIEW OPTION. On a real catalogue it reads as a second flag bleeding
  /// through rather than as a silhouette — Andorra's coat of arms and
  /// Azerbaijan's crescent land right behind the name, and a flag with a
  /// central disc (Bangladesh, Japan) becomes an unexplained blob. The
  /// colour-only version below carries the same identity with none of that.
  final bool showFlagWash;

  const CountryBackdrop({
    super.key,
    required this.flagAsset,
    required this.flagMapAsset,
    required this.backgroundAsset,
    required this.tint,
    this.showFlagWash = false,
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. The brand's ground. Softened, because the card's text sits
              // straight on it and a full-strength photograph would win.
              if (backgroundAsset != null)
                Opacity(
                  // Low: the card's name and price sit straight on this, and
                  // at 0.30 the brand photo's own route lines and pins were
                  // competing with the text on every row.
                  opacity: 0.16,
                  child: Image.asset(
                    backgroundAsset!,
                    fit: BoxFit.cover,
                    // A brand whose file is missing or unreadable must not
                    // take the card down with it.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              // Strongest at the outer edge, gone by the middle, so the name
              // and price never sit on colour they have to fight.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: <Color>[tint.withValues(alpha: 0.22), tint.withValues(alpha: 0)],
                    stops: const <double>[0, 0.72],
                  ),
                ),
              ),
              // 2. The destination's flag-map, centred on the brand ground.
              if (flagMapAsset != null)
                Align(
                  // Top-right, and short enough to clear the Select button in
                  // the bottom-right corner: at full height the map ran under
                  // the button on every card that had one.
                  alignment: Alignment.topRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.34,
                    heightFactor: 0.62,
                    child: Padding(
                      padding: const EdgeInsets.only(right: Gap.lg, top: Gap.sm),
                      child: SvgPicture.asset(flagMapAsset!, fit: BoxFit.contain),
                    ),
                  ),
                )
              // 3. Otherwise the soft landmass suggestion: deliberately NOT a
              // country shape. A generic blob claiming to be Austria would be
              // a lie — as an unclaimed swell of the destination's own colour
              // it is just depth.
              else if (!showFlagWash)
                Positioned(
                  right: -52,
                  top: -44,
                  bottom: -60,
                  width: 210,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tint.withValues(alpha: 0.13),
                    ),
                  ),
                ),
              if (showFlagWash && flagAsset != null)
                Positioned(
                  right: -28,
                  top: -18,
                  bottom: -18,
                  child: Opacity(
                    // Low enough to read as a watermark rather than a second
                    // flag: the card already carries a crisp one in its badge.
                    opacity: 0.16,
                    child: Transform.rotate(
                      angle: -0.18,
                      child: SvgPicture.asset(flagAsset!, fit: BoxFit.contain),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// One destination, as a card.
///
/// [coveredCodes] turns it into the REGIONAL variant: instead of one country's
/// flag it scatters the flags it covers and counts the rest in a pill, which
/// is what a "Europe" or "Worldwide" pack has to say instead of a shape.
class DestinationCard extends StatelessWidget {
  final String code;
  final String title;
  final String subtitle;
  final String? price;
  final String? priceCaption;
  final String actionLabel;
  final VoidCallback onTap;
  final List<String> coveredCodes;

  /// REVIEW OPTION — see [CountryBackdrop.showFlagWash].
  final bool showFlagWash;

  /// The brand's card background, already resolved to an asset path by the
  /// caller (which is the layer that knows which brand is running). Passed in
  /// rather than read here so this widget stays free of provider plumbing,
  /// the same way it takes its colours from the theme rather than the config.
  final String? backgroundAsset;

  const DestinationCard({
    super.key,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.price,
    this.priceCaption,
    this.coveredCodes = const <String>[],
    this.showFlagWash = false,
    this.backgroundAsset,
  });

  bool get _regional => coveredCodes.length > 1;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.card);
    final flag = countryFlagAsset(code);
    final value = countryColorValue(code);
    // A destination with no flag (a regional pseudo-code) still gets a card;
    // it borrows the brand's accent rather than inventing a colour.
    final tint = value == null ? t.accent : Color(value);

    return AppPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: t.card,
          boxShadow: Shadows.float(t.primary),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              CountryBackdrop(
                flagAsset: flag,
                flagMapAsset: countryFlagMapAsset(code),
                backgroundAsset: backgroundAsset,
                tint: tint,
                showFlagWash: showFlagWash,
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_regional)
                      _FlagCluster(codes: coveredCodes)
                    else if (flag != null)
                      FlagBadge(flag, size: 44, shadow: Shadows.badge)
                    else
                      _CodeDisc(code: code, tint: tint),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppType.cardTitle.copyWith(color: t.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(subtitle, style: AppType.caption.copyWith(color: t.inkMuted)),
                          const SizedBox(height: Gap.md),
                          Row(
                            children: [
                              if (price != null)
                                _PricePill(price: price!, caption: priceCaption),
                              const Spacer(),
                              _SelectButton(label: actionLabel, onTap: onTap),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The regional variant's identity: the flags it covers, overlapped, with the
/// ones that did not fit counted in a pill.
class _FlagCluster extends StatelessWidget {
  final List<String> codes;

  const _FlagCluster({required this.codes});

  static const int _shown = 3;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final assets = <String>[];
    for (final c in codes) {
      final a = countryFlagAsset(c);
      if (a != null) assets.add(a);
    }
    final visible = assets.take(_shown).toList();
    final rest = codes.length - visible.length;

    return SizedBox(
      width: 48,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              top: i * 9,
              left: i * 7,
              child: FlagBadge(visible[i], size: 26, shadow: Shadows.badge),
            ),
          if (rest > 0)
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 1),
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text('+$rest', style: AppType.caption.copyWith(color: t.onPrimary)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The fallback when a code has no flag: its letters on its own tint.
class _CodeDisc extends StatelessWidget {
  final String code;
  final Color tint;

  const _CodeDisc({required this.code, required this.tint});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        code.toUpperCase(),
        style: AppType.captionStrong.copyWith(color: t.primary),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final String price;
  final String? caption;

  const _PricePill({required this.price, required this.caption});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (caption != null) ...[
          Text(caption!, style: AppType.caption.copyWith(color: t.inkMuted)),
          const SizedBox(width: Gap.xs),
        ],
        Text(price, style: AppType.bodyStrong.copyWith(color: ShopTokens.of(context).display)),
      ],
    );
  }
}

/// The card's own action, in the brand's call-to-action pair — the canvas's
/// "Auswählen / Choisir / Select".
class _SelectButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SelectButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const shape = StadiumBorder();
    return Material(
      color: t.cta,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
          child: Text(label, style: AppType.chip.copyWith(color: t.ctaText)),
        ),
      ),
    );
  }
}

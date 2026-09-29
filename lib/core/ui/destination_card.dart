/// One destination, as a Store-list card: the brand's own gradient, the
/// country's flag and name on it, and the country drawn small at the end.
///
/// The card used to put its content ON TOP of the live pack-art renderer, and
/// every legibility problem it had came from that — text over a picture whose
/// colours belong to a flag, not to the app. This version inverts it: the
/// ground is the brand's, the art is an inset, and nothing has to be rescued
/// with scrims. `PackArt` stays exactly where it earns its keep — the pack
/// cards and the detail hero, where the art IS the subject.
///
/// The gradient is `accent -> surface`, the same pair the Profile identity
/// card and the pack-detail hero already use, so this is the established
/// brand-card treatment rather than a third look.
library;

import 'package:flutter/material.dart';

import '../i18n/country_flags.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'flag_glyph.dart';

class DestinationCard extends StatelessWidget {
  final String code;
  final String title;
  final String subtitle;
  final String? price;
  final String? priceCaption;
  final String actionLabel;
  final VoidCallback onTap;

  const DestinationCard({
    super.key,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.price,
    this.priceCaption,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.card);
    final flag = countryFlagAsset(code);
    final map = countryFlagMapAsset(code);
    // The country at the end of the row: its map where the curated set has
    // one, its flag where it does not. Only a code with neither — a regional
    // pseudo-code — leaves the slot out, rather than holding an empty one.
    final Widget? inset = map != null
        ? _MapInset(asset: map)
        : flag != null
            ? _FlagInset(asset: flag)
            : null;

    return AppPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[t.accent, t.surface],
          ),
          boxShadow: Shadows.float(t.primary),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    // The badge sits with the title, not with the middle of a
                    // three-line block.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (flag != null)
                        FlagBadge(flag, size: 40, shadow: Shadows.badge)
                      else
                        _CodeDisc(code: code),
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
                            if (price != null) ...[
                              const SizedBox(height: Gap.sm),
                              _Price(price: price!, caption: priceCaption),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (inset != null) ...[
                  const SizedBox(width: Gap.md),
                  inset,
                ],
                const SizedBox(width: Gap.md),
                _SelectButton(label: actionLabel, onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The slot at the end of the row. 4:3, which is the map artwork's own ratio.
abstract final class _Inset {
  static const double width = 72;
  static const double height = 54;
}

/// The country's flag, for the destinations the curated map set does not
/// cover — about a third of the catalogue. The artwork is 1:1, so it sits in
/// the slot as a square tile rather than being stretched to fill it.
class _FlagInset extends StatelessWidget {
  final String asset;

  const _FlagInset({required this.asset});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _Inset.width,
        height: _Inset.height,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.badge),
            child: FlagGlyph(asset, size: _Inset.height),
          ),
        ),
      );
}

/// The country, small, at the end of the row.
///
/// Decoded at display size rather than at the file's own 480x360: a list of
/// these at full resolution costs about 690 KB of image cache each, and the
/// cache holds every row the viewport has already passed.
class _MapInset extends StatelessWidget {
  final String asset;

  const _MapInset({required this.asset});

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Image.asset(
      asset,
      width: _Inset.width,
      height: _Inset.height,
      fit: BoxFit.contain,
      cacheWidth: (_Inset.width * ratio).round(),
      filterQuality: FilterQuality.medium,
      // The set is curated and checked against `kFlagMapCodes` before we get
      // here, so this only fires if a file is corrupt — in which case the card
      // is the same finished card an uncovered country gets.
      errorBuilder: (_, _, _) => const SizedBox(width: _Inset.width, height: _Inset.height),
    );
  }
}

/// The fallback when a code has no flag: its letters on its own tint.
class _CodeDisc extends StatelessWidget {
  final String code;

  const _CodeDisc({required this.code});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.card, shape: BoxShape.circle),
      child: Text(
        code.toUpperCase(),
        style: AppType.captionStrong.copyWith(color: t.primary),
      ),
    );
  }
}

/// "From EUR 4.00" — the caption quiet, the number not.
///
/// One paragraph rather than a Row of two Texts: the inset leaves this column
/// narrow, and French's "A partir de" is half again the width of English's
/// "From". A Row overflows there; a paragraph wraps.
class _Price extends StatelessWidget {
  final String price;
  final String? caption;

  const _Price({required this.price, required this.caption});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final strong = AppType.bodyStrong.copyWith(color: t.primary);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          if (caption != null)
            TextSpan(
              text: '$caption ',
              style: AppType.caption.copyWith(color: t.inkMuted),
            ),
          TextSpan(text: price, style: strong),
        ],
      ),
      style: strong,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
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

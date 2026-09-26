import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// A country's flag, drawn from the SVG bundled for it.
///
/// Every flag in the app goes through this. Callers resolve the asset first
/// with `countryFlagAsset` and fall back to the ISO letters when it returns
/// `null`, so this widget never has to render an absence.
///
/// [size] is the side of the square the flag fills. The artwork is 1:1
/// (lipis/flag-icons `1x1`), composed to survive being cropped to a circle.
///
/// This replaced a flag EMOJI, which is why the previous version of this file
/// was three times as long: a glyph sits on a text baseline with the font's
/// full ascent and descent reserved around it, which painted the flag below
/// the centre of a perfectly centred circle and needed a `TextHeightBehavior`
/// and a forced strut to undo. A picture has no baseline, so none of that
/// applies.
class FlagGlyph extends StatelessWidget {
  /// The asset path from `countryFlagAsset`, not a country code — the caller
  /// has already had to resolve it to know whether to draw a flag at all.
  final String asset;

  final double size;

  const FlagGlyph(this.asset, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
}

/// A flag in a circle, filling it completely.
///
/// Worth its own widget because getting the flag to actually reach the edge
/// is not obvious, and four screens had each hand-rolled the badge slightly
/// differently. A `Container` with both a `border` and an `alignment` lays
/// its child out INSIDE the border and then centres it, so a flag given the
/// badge's own diameter came back 2px short on every side and the disc's
/// background showed as a pale rim — most visible on the dark destination
/// header, where the ring is white.
///
/// So: no `alignment` (the child gets tight constraints and fills), the ring
/// moves to `foregroundDecoration` where it paints OVER the flag instead of
/// insetting it, and the artwork is scaled a few percent past the circle so
/// that anti-aliasing at the clip edge has colour to work with rather than
/// background. Deliberately oversized and clipped, never snug.
class FlagBadge extends StatelessWidget {
  final String asset;
  final double size;

  /// A ring drawn on top of the flag, for a badge that needs an edge against
  /// its ground — the destination header's white circle on dark teal.
  final Color? ring;
  final double ringWidth;

  /// [Shadows.card] on the header's badge, nothing in a list row.
  final List<BoxShadow> shadow;

  const FlagBadge(
    this.asset, {
    super.key,
    this.size = 44,
    this.ring,
    this.ringWidth = 2,
    this.shadow = Shadows.none,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadow),
        foregroundDecoration: ring == null
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring!, width: ringWidth),
              ),
        // 1.06, not 1.0: the clip is a circle and the artwork is a square, so
        // the four points where they touch are exactly the places a hairline
        // of nothing would show.
        child: Transform.scale(
          scale: 1.06,
          child: FlagGlyph(asset, size: size),
        ),
      );
}

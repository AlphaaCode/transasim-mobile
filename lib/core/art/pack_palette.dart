/// The pack-art palette, derived from `brand.colors` and nothing else.
///
/// A port of `palette()` in the web renderer (`art.ts`, commit eba1820),
/// formula for formula, because the two have to agree: the same brand must
/// produce the same background on the site and in the app. The expected
/// outputs for all three brands are pinned in `pack_palette_test.dart`
/// against the web team's own `palettes-attendues.json`.
///
/// No per-client configuration exists or may be added. A new brand gets its
/// background from its three colours, which is the rule the web renderer was
/// built around and the reason this file takes `primary`/`accent`/`cta` rather
/// than reading anything else.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Whether the background reads as a light or a dark surface.
enum PackTone { light, dark }

@immutable
class PackPalette {
  final PackTone tone;
  final Color primary;
  final Color bgTop;
  final Color bgBottom;

  /// Pins, dotted leaders, the "+N" pill, and the decorative strokes on a dark
  /// ground. The most saturated brand colour that still separates from the
  /// middle of the gradient.
  final Color highlight;

  const PackPalette({
    required this.tone,
    required this.primary,
    required this.bgTop,
    required this.bgBottom,
    required this.highlight,
  });

  bool get isLight => tone == PackTone.light;

  /// The text on the "+N" pill: white or near-black, whichever separates
  /// further from [highlight].
  Color get onHighlight =>
      packContrast(ArtInk.white, highlight) >=
              packContrast(ArtInk.badgeDark, highlight)
          ? ArtInk.white
          : ArtInk.badgeDark;

  static PackPalette of(Color primary, Color accent, Color cta) {
    // The threshold the web uses to decide light vs dark. eSimple's luminous
    // turquoise lands above it and gets a pale ground; Sabily and Odyssey fall
    // below and get a dark one.
    final light = packLuminance(primary) > 0.22;
    final bgTop = packMix(primary, ArtInk.white, light ? 0.86 : 0.06);
    final bgBottom = light ? packMix(primary, ArtInk.white, 0.55) : packMix(primary, ArtInk.black, 0.38);
    final bgMid = packMix(bgTop, bgBottom, 0.5);

    // Most saturated first, among those that clear 2:1 against the middle of
    // the gradient — below that the pin does not read at all.
    final candidates = <Color>[cta, accent, primary]
        .where((c) => packContrast(c, bgMid) >= 2)
        .toList()
      ..sort((a, b) => packSaturation(b).compareTo(packSaturation(a)));

    return PackPalette(
      tone: light ? PackTone.light : PackTone.dark,
      primary: primary,
      bgTop: bgTop,
      bgBottom: bgBottom,
      highlight: candidates.isNotEmpty
          ? candidates.first
          : packEnsureContrast(primary, bgMid, 3),
    );
  }
}

int _ch(double v) => v.round().clamp(0, 255);

/// Linear interpolation per channel in sRGB 0–255, rounded — `mix` in art.ts.
///
/// Rounded at each step, not at the end: the web rounds here too, and the
/// expected hex values in the fixtures only reproduce if this does the same.
Color packMix(Color a, Color b, double t) => Color.fromARGB(
      255,
      _ch((a.r * 255) + ((b.r * 255) - (a.r * 255)) * t),
      _ch((a.g * 255) + ((b.g * 255) - (a.g * 255)) * t),
      _ch((a.b * 255) + ((b.b * 255) - (a.b * 255)) * t),
    );

/// WCAG 2.0 relative luminance.
double packLuminance(Color c) {
  double lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

/// WCAG contrast ratio, lighter over darker.
double packContrast(Color a, Color b) {
  final x = packLuminance(a), y = packLuminance(b);
  final hi = math.max(x, y), lo = math.min(x, y);
  return (hi + 0.05) / (lo + 0.05);
}

/// HSV-style saturation: `(max - min) / max`.
double packSaturation(Color c) {
  final mx = math.max(c.r, math.max(c.g, c.b));
  final mn = math.min(c.r, math.min(c.g, c.b));
  return mx == 0 ? 0 : (mx - mn) / mx;
}

/// Nudges [color] toward black or white in 0.05 steps until it clears [ratio]
/// against [against]. Only used when no brand colour qualifies.
Color packEnsureContrast(Color color, Color against, double ratio) {
  if (packContrast(color, against) >= ratio) return color;
  final target = packLuminance(color) <= packLuminance(against) ? ArtInk.black : ArtInk.white;
  for (var t = 0.05; t <= 1.0; t += 0.05) {
    final c = packMix(color, target, t);
    if (packContrast(c, against) >= ratio) return c;
  }
  return target;
}

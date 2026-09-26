/// A country drawn as its own outline.
///
/// The paths come from `country_shapes.g.dart` — Natural Earth 1:110m,
/// normalised into a 0..1 box at build time — so nothing here projects,
/// simplifies or reprojects at runtime. This file only parses and paints.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/country_shapes.g.dart';

/// Parsed [Path]s, kept for the life of the isolate.
///
/// A destination list rebuilds constantly while it scrolls, and re-parsing a
/// 140-point outline on every frame is the kind of thing that only shows up
/// as jank on the cheapest device in the fleet. There are at most 171 of
/// these and they never change.
final Map<String, Path> _cache = <String, Path>{};

Path? countryPath(String alpha2) {
  final key = alpha2.toLowerCase();
  final hit = _cache[key];
  if (hit != null) return hit;
  final raw = kCountryShapes[key];
  if (raw == null) return null;
  return _cache[key] = _parse(raw);
}

/// Whether this country has an outline at all. 171 of ~200 destinations do;
/// the rest are small states the 110m dataset does not carry.
bool hasCountryShape(String alpha2) => kCountryShapes.containsKey(alpha2.toLowerCase());

/// Width / height of the outline, so a caller can avoid stretching it.
double countryAspect(String alpha2) => kCountryAspect[alpha2.toLowerCase()] ?? 1;

Path _parse(String d) {
  final path = Path();
  var i = 0;
  double number() {
    final start = i;
    while (i < d.length && (d.codeUnitAt(i) == 0x2D || d.codeUnitAt(i) == 0x2E ||
        (d.codeUnitAt(i) >= 0x30 && d.codeUnitAt(i) <= 0x39))) {
      i++;
    }
    return double.parse(d.substring(start, i));
  }

  while (i < d.length) {
    final c = d[i];
    if (c == 'M' || c == 'L') {
      i++;
      final x = number();
      i++; // the single space between the pair
      final y = number();
      if (c == 'M') {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    } else if (c == 'Z') {
      path.close();
      i++;
    } else {
      i++;
    }
  }
  return path;
}

/// Paints a country's outline, scaled to fit its box without distortion.
class CountryOutline extends StatelessWidget {
  final String alpha2;
  final Color color;

  /// Drawn as a filled silhouette by default; an outline when false.
  final bool filled;

  const CountryOutline({
    super.key,
    required this.alpha2,
    required this.color,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final path = countryPath(alpha2);
    if (path == null) return const SizedBox.shrink();
    return CustomPaint(painter: _ShapePainter(path, color, filled), size: Size.infinite);
  }
}

class _ShapePainter extends CustomPainter {
  final Path path;
  final Color color;
  final bool filled;

  const _ShapePainter(this.path, this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    // The generator already centred the shape inside a square 0..1 box, so a
    // single uniform scale is the whole transform — no aspect maths here.
    final side = size.shortestSide;
    final dx = (size.width - side) / 2;
    final dy = (size.height - side) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(side);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        // A stroke scales with the canvas, so it is divided back out to stay
        // a hairline whatever size the card is.
        ..strokeWidth = filled ? 0 : 2 / side
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.path != path || old.color != color || old.filled != filled;
}

/// The faint topographic wash the art area sits on.
///
/// Contour lines rather than a flat tint, because the reference draws the
/// silhouette as if it were lifted off a map. Sine curves, not real terrain —
/// nobody reads elevation off a 90px card, and real contours would be another
/// dataset for no gain.
class TopographicWash extends StatelessWidget {
  final Color line;

  const TopographicWash({super.key, required this.line});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ContourPainter(line), size: Size.infinite);
}

class _ContourPainter extends CustomPainter {
  final Color line;

  const _ContourPainter(this.line);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    const rows = 7;
    for (var r = 0; r < rows; r++) {
      final path = Path();
      final base = size.height * (r + 0.5) / rows;
      path.moveTo(0, base);
      for (var x = 0.0; x <= size.width; x += 8) {
        // Two offset sines so the lines drift apart and together like a
        // contour map instead of marching in parallel.
        final y = base +
            math.sin(x / 52 + r * 0.9) * 7 +
            math.sin(x / 23 + r * 1.7) * 2.5;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ContourPainter old) => old.line != line;
}

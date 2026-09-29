/// The pack-card background, drawn natively.
///
/// A port of `art.ts` (web, commit eba1820) to a `CustomPainter`, following
/// LISEZMOI §§3–5. The web serves this as an SVG; the app cannot render that
/// SVG, because it leans on `feDropShadow` and on nested SVG data-URIs for the
/// flags, and `flutter_svg` implements neither. So the drawing is reproduced
/// rather than the file consumed.
///
/// Everything is laid out in a fixed 400x225 frame and scaled to whatever the
/// card is, which keeps every constant here identical to the web's.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme/app_theme.dart';
import 'geo_data.dart';
import 'geo_projection.dart';
import 'pack_palette.dart';

/// The design frame. Every coordinate below is in these units.
const double kArtWidth = 400;
const double kArtHeight = 225;

/// A flag ready to draw: its picture and its aspect ratio.
class PackFlag {
  final ui.Picture picture;
  final Size size;

  const PackFlag(this.picture, this.size);

  double get ratio => size.height == 0 ? 1.5 : size.width / size.height;
}

class PackArtPainter extends CustomPainter {
  final PackPalette palette;
  final GeoData geo;

  /// Covered countries, ISO alpha-3, as the backend gives them.
  final List<String> codes;

  /// The destination being viewed — highlighted on a zone, and the globe is
  /// turned toward it.
  final String? current;

  /// Flags already decoded, keyed alpha-3. Missing entries simply draw
  /// without a flag rather than blocking the frame.
  final Map<String, PackFlag> flags;

  const PackArtPainter({
    required this.palette,
    required this.geo,
    required this.codes,
    required this.flags,
    this.current,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // "cover": fill the card and overflow symmetrically, matching the web's
    // preserveAspectRatio="xMidYMid slice".
    final k = math.max(size.width / kArtWidth, size.height / kArtHeight);
    canvas.translate(
      (size.width - kArtWidth * k) / 2,
      (size.height - kArtHeight * k) / 2,
    );
    canvas.scale(k);
    canvas.clipRect(const Rect.fromLTWH(0, 0, kArtWidth, kArtHeight));

    _backdrop(canvas);

    final unique = <String>{...codes}.toList();
    if (unique.length <= 1) {
      _countryArt(canvas, unique.isNotEmpty ? unique.first : (current ?? ''));
    } else if (unique.every((c) => !geo.countries.containsKey(c))) {
      _countryArt(canvas, '');
    } else {
      _regionArt(canvas, unique);
    }
    canvas.restore();
  }

  // ── §4.1 the common decor ──────────────────────────────────────────────

  /// The drop shadow every raised element carries: (0, 6), sigma 7.
  void _withShadow(Canvas canvas, Path path, void Function() draw) {
    canvas.save();
    canvas.translate(0, 6);
    canvas.drawPath(
      path,
      Paint()
        ..color = ArtInk.black.withValues(alpha: palette.isLight ? 0.22 : 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();
    draw();
  }

  void _backdrop(Canvas canvas) {
    final light = palette.isLight;
    final globeA = packMix(palette.primary, ArtInk.white, light ? 0.35 : 0.16);
    final globeB = packMix(palette.primary, ArtInk.white, light ? 0.5 : 0.1);
    final line = light ? ArtInk.white : palette.highlight;

    // 1. the ground
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, kArtWidth, kArtHeight),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0.35 * kArtWidth, kArtHeight),
          [palette.bgTop, palette.bgBottom],
        ),
    );

    // 2. the low sphere, bottom-left
    canvas.drawCircle(
      const Offset(-30, 300),
      190,
      Paint()..color = globeB.withValues(alpha: light ? 0.45 : 0.55),
    );

    // 3. the big sphere, bottom-right
    const centre = Offset(345, 345);
    const radius = 265.0;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          // The SVG gradient's cx/cy/r are fractions of the circle's own box.
          centre + const Offset((0.35 - 0.5) * 2 * radius, (0.3 - 0.5) * 2 * radius),
          0.8 * 2 * radius,
          [
            globeA.withValues(alpha: light ? 0.35 : 0.55),
            globeA.withValues(alpha: light ? 0.95 : 0.9),
          ],
          [0.0, 1.0],
        ),
    );

    // 4. meridians
    final meridian = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = line.withValues(alpha: light ? 0.5 : 0.28);
    for (final r in const [
      Size(265, 120),
      Size(265, 210),
      Size(120, 265),
      Size(215, 265),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: r.width * 2, height: r.height * 2),
        meridian,
      );
    }
    final arc = Path()
      ..moveTo(-40, 150)
      ..quadraticBezierTo(120, 70, 300, 40)
      // T: reflect the previous control point through the current point.
      ..quadraticBezierTo(480, 10, 460, 0);
    canvas.drawPath(arc, meridian);

    // 5. the sphere's edge
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = (light ? ArtInk.white : palette.highlight)
            .withValues(alpha: light ? 0.7 : 0.55),
    );

    // 6. the highlight
    canvas.drawCircle(
      const Offset(330, 40),
      70,
      Paint()..color = ArtInk.white.withValues(alpha: light ? 0.25 : 0.04),
    );
  }

  // ── §4.2 the pin ───────────────────────────────────────────────────────

  void _pin(Canvas canvas, double x, double y) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y + 2), width: 22, height: 7),
      Paint()..color = ArtInk.black.withValues(alpha: 0.18),
    );
    final drop = Path()
      ..moveTo(x, y)
      ..cubicTo(x - 4, y - 12, x - 13, y - 17, x - 13, y - 28)
      ..arcToPoint(Offset(x + 13, y - 28), radius: const Radius.circular(13), clockwise: true)
      ..cubicTo(x + 13, y - 17, x + 4, y - 12, x, y)
      ..close();
    canvas.drawPath(drop, Paint()..color = palette.highlight);
    canvas.drawPath(
      drop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ArtInk.white,
    );
    canvas.drawCircle(Offset(x, y - 28), 5, Paint()..color = ArtInk.white);
  }

  // ── §4.3 one country: its flag, clipped to its silhouette ──────────────

  /// §4.4's fallback for territories with no usable silhouette.
  static final _wavingFlag = (
    d: 'M0 10 Q 42.5 -6 85 8 T 170 6 L 170 108 Q 127.5 122 85 108 T 0 112 Z',
    box: <double>[0, -6, 170, 126],
  );

  void _countryArt(Canvas canvas, String code) {
    final shape = geo.shapes[code];
    final usable = shape != null && shape.fill >= 0.05;
    final d = usable ? shape.d : _wavingFlag.d;
    final box = usable ? shape.box : _wavingFlag.box;
    final path = usable ? (geo.shapePath(code) ?? parseSvgPathData(d)) : parseSvgPathData(d);

    final bx = box[0], by = box[1], bw = box[2], bh = box[3];
    final k = math.min(215 / bw, 170 / bh);
    final tx = 205 - (bx + bw / 2) * k;
    final ty = 110 - (by + bh / 2) * k;
    final pinX = math.max(34.0, tx + bx * k - 28);
    const pinY = 118.0;

    // Dotted leader, drawn under everything else.
    final leader = Path()
      ..moveTo(pinX, pinY - 28)
      ..quadraticBezierTo(
        pinX + 60,
        pinY - 120,
        tx + (bx + bw) * k + 30,
        ty + by * k + 10,
      );
    canvas.drawPath(
      dashPath(leader, dashArray: CircularIntervalList<double>(<double>[2, 5])),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = (palette.isLight ? ArtInk.white : palette.highlight)
            .withValues(alpha: 0.8),
    );

    canvas.save();
    canvas.translate(tx, ty);
    canvas.scale(k);

    // White body and outline, with the shadow. The stroke is 5/k so it lands
    // at ~5px on screen whatever the country's scale.
    _withShadow(canvas, path, () {
      canvas.drawPath(path, Paint()..color = ArtInk.white);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 / k
          ..strokeJoin = StrokeJoin.round
          ..color = ArtInk.white,
      );
    });

    final flag = flags[code];
    if (flag == null) {
      canvas.drawPath(path, Paint()..color = palette.highlight);
    } else {
      canvas.save();
      canvas.clipPath(path);
      _drawFlagCover(canvas, flag, bx, by, bw, bh);
      canvas.restore();
    }
    canvas.restore();

    _pin(canvas, pinX, pinY);
  }

  /// §4.3 step 4: fill the box without distorting the flag.
  void _drawFlagCover(Canvas canvas, PackFlag flag, double x, double y, double w, double h) {
    final iw = math.max(w, h * flag.ratio);
    final ih = iw / flag.ratio;
    canvas.save();
    canvas.translate(x + (w - iw) / 2, y + (h - ih) / 2);
    canvas.scale(iw / flag.size.width, ih / flag.size.height);
    canvas.drawPicture(flag.picture);
    canvas.restore();
  }

  // ── §4.5 a zone, or the globe ──────────────────────────────────────────

  void _regionArt(Canvas canvas, List<String> unique) {
    final cov = Coverage.classify(unique, geo.countries);
    final light = palette.isLight;
    final covered = <String>{...cov.known};

    final landColor = light ? ArtInk.white : packMix(palette.primary, ArtInk.white, 0.14);
    final coveredColor =
        light ? ArtInk.white : packMix(palette.primary, ArtInk.white, 0.86);
    final borderColor = light
        ? packMix(palette.primary, ArtInk.white, 0.25)
        : packMix(palette.primary, ArtInk.black, 0.1);

    late final GeoProjection proj;
    List<String> markerCandidates = cov.known;
    bool Function(LonLat) markerVisible = (_) => true;

    if (!cov.isWorld) {
      // Zone: framed on the CORE of the coverage. Trimming the outer 3% each
      // way stops one far-flung territory from zooming the whole map out.
      final p = AzimuthalEqualAreaProjection(cov.centre);
      final pts = <LonLat>[for (final c in cov.known) ...geo.countries[c]!.outline];
      if (pts.isEmpty) return;
      p.fitExtent(pts, 0, 0, kArtWidth, kArtHeight);
      final xs = <double>[], ys = <double>[];
      for (final q in pts) {
        final xy = p.project(q);
        if (xy == null) continue;
        xs.add(xy.x);
        ys.add(xy.y);
      }
      final x0 = quantileAt(xs, 0.03), x1 = quantileAt(xs, 0.97);
      final y0 = quantileAt(ys, 0.03), y1 = quantileAt(ys, 0.97);
      final core = <LonLat>[];
      for (final q in pts) {
        final xy = p.project(q);
        if (xy == null) continue;
        if (xy.x >= x0 && xy.x <= x1 && xy.y >= y0 && xy.y <= y1) core.add(q);
      }
      p.fitExtent(core.isNotEmpty ? core : pts, 40, 34, kArtWidth - 40, kArtHeight - 16);
      proj = p;

      canvas.drawRect(
        const Rect.fromLTWH(0, 0, kArtWidth, kArtHeight),
        Paint()
          ..color = (light
                  ? packMix(palette.primary, ArtInk.white, 0.72)
                  : packMix(palette.primary, ArtInk.black, 0.2))
              .withValues(alpha: light ? 0.35 : 0.25),
      );
      _drawLand(canvas, proj, covered, landColor, light ? 0.38 : 0.9);
      _drawCovered(canvas, proj, cov.known, coveredColor, borderColor, 0.6);
    } else {
      // Globe, turned toward the destination — or Europe when there is none.
      final target = current != null && geo.countries.containsKey(current)
          ? geo.countries[current!]!.centre
          : const (10.0, 30.0);
      const cx = 200.0, cy = 118.0, r = 96.0;
      final tilted = (target.$1, target.$2.clamp(-30.0, 30.0) * 0.6);
      final p = OrthographicProjection(tilted, scale: r, tx: cx, ty: cy);
      proj = p;

      final sphere = Path()..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: r));
      _withShadow(canvas, sphere, () {
        canvas.drawCircle(
          const Offset(cx, cy),
          r,
          Paint()
            ..shader = ui.Gradient.radial(
              const Offset(cx + (0.35 - 0.5) * 2 * r, cy + (0.3 - 0.5) * 2 * r),
              0.85 * 2 * r,
              [
                packMix(palette.primary, ArtInk.white, light ? 0.3 : 0.25),
                packMix(palette.primary, ArtInk.black, light ? 0.12 : 0.25),
              ],
              [0.0, 1.0],
            ),
        );
      });

      canvas.save();
      canvas.clipPath(sphere);
      _graticule(canvas, p);
      _drawLand(canvas, proj, covered, ArtInk.white, 0.3);
      _drawCovered(canvas, proj, cov.known, coveredColor, borderColor, 0.5);
      canvas.restore();

      canvas.drawCircle(
        const Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ArtInk.white,
      );

      markerVisible = (c) => geoDistance(c, target) < 1.1;
    }

    final markers = _pickMarkers(markerCandidates, proj, markerVisible);
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final flag = flags[m.$1];
      if (flag == null) {
        _pin(canvas, m.$2, m.$3);
      } else {
        _flagPin(canvas, m.$2, m.$3, flag);
      }
    }
    final more = unique.length - markers.length;
    if (more > 0) _morePill(canvas, more, kArtWidth - 14, 26);
  }

  Path _ringsPath(GeoProjection proj, List<List<LonLat>> rings) {
    final path = Path();
    final ortho = proj is OrthographicProjection ? proj : null;
    for (final ring in rings) {
      var started = false;
      for (final p in ring) {
        // On the globe, a hidden vertex is pushed out to the limb so the
        // polygon closes along the horizon instead of tearing (LISEZMOI §5.4).
        final xy = ortho != null ? ortho.projectClamped(p) : proj.project(p);
        if (xy == null) continue;
        if (!started) {
          path.moveTo(xy.x, xy.y);
          started = true;
        } else {
          path.lineTo(xy.x, xy.y);
        }
      }
      if (started) path.close();
    }
    return path;
  }

  void _drawLand(
    Canvas canvas,
    GeoProjection proj,
    Set<String> covered,
    Color color,
    double opacity,
  ) {
    final path = Path()..fillType = PathFillType.evenOdd;
    geo.countries.forEach((code, c) {
      if (covered.contains(code)) return;
      path.addPath(_ringsPath(proj, c.rings), Offset.zero);
    });
    for (final o in geo.others) {
      path.addPath(_ringsPath(proj, o), Offset.zero);
    }
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  void _drawCovered(
    Canvas canvas,
    GeoProjection proj,
    List<String> codes,
    Color fill,
    Color border,
    double width,
  ) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final code in codes) {
      path.addPath(_ringsPath(proj, geo.countries[code]!.rings), Offset.zero);
    }
    _withShadow(canvas, path, () {
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..color = border,
      );
    });
  }

  void _graticule(Canvas canvas, OrthographicProjection proj) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = ArtInk.white.withValues(alpha: 0.25);
    // Every 10 degrees, as d3.geoGraticule10 does.
    for (var lon = -180.0; lon <= 180.0; lon += 10) {
      final path = Path();
      var started = false;
      for (var lat = -80.0; lat <= 80.0; lat += 2) {
        final xy = proj.project((lon, lat));
        if (xy == null) {
          started = false;
          continue;
        }
        started ? path.lineTo(xy.x, xy.y) : path.moveTo(xy.x, xy.y);
        started = true;
      }
      canvas.drawPath(path, paint);
    }
    for (var lat = -80.0; lat <= 80.0; lat += 10) {
      final path = Path();
      var started = false;
      for (var lon = -180.0; lon <= 180.0; lon += 2) {
        final xy = proj.project((lon, lat));
        if (xy == null) {
          started = false;
          continue;
        }
        started ? path.lineTo(xy.x, xy.y) : path.moveTo(xy.x, xy.y);
        started = true;
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Up to three countries to pin: the destination first, then the largest,
  /// spaced apart and clear of the "+N" corner.
  List<(String, double, double)> _pickMarkers(
    List<String> known,
    GeoProjection proj,
    bool Function(LonLat) visible,
  ) {
    final ranked = [...known]
      ..sort((a, b) => geo.countries[b]!.area.compareTo(geo.countries[a]!.area));
    if (current != null && known.contains(current)) ranked.insert(0, current!);

    final chosen = <(String, double, double)>[];
    for (final code in ranked) {
      if (chosen.length == 3) break;
      final c = geo.countries[code]!.centre;
      if (!visible(c)) continue;
      final xy = proj.project(c);
      if (xy == null) continue;
      final x = xy.x, y = xy.y;
      if (x < 40 || x > kArtWidth - 40 || y < 50 || y > kArtHeight - 12) continue;
      if (x > kArtWidth - 100 && y < 72) continue; // the "+N" corner
      if (chosen.any((o) => o.$1 == code || math.sqrt(math.pow(o.$2 - x, 2) + math.pow(o.$3 - y, 2)) < 58)) {
        continue;
      }
      chosen.add((code, x, y));
    }
    return chosen;
  }

  void _flagPin(Canvas canvas, double x, double y, PackFlag flag) {
    const r = 13.0;
    final body = Path()
      ..moveTo(x, y)
      ..relativeLineTo(-7, -9)
      ..arcToPoint(Offset(x + 7, y - 9), radius: const Radius.circular(r + 3), clockwise: true, largeArc: true)
      ..close();
    final disc = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, y - 9 - r), radius: r + 3));
    final together = Path.combine(PathOperation.union, body, disc);
    _withShadow(canvas, together, () {
      canvas.drawPath(together, Paint()..color = ArtInk.white);
    });

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset(x, y - 9 - r), radius: r)),
    );
    final iw = math.max(2 * r, 2 * r * flag.ratio);
    final ih = iw / flag.ratio;
    _drawFlagCoverAt(canvas, flag, x - iw / 2, y - 9 - r - ih / 2, iw, ih);
    canvas.restore();
  }

  void _drawFlagCoverAt(Canvas canvas, PackFlag flag, double x, double y, double w, double h) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(w / flag.size.width, h / flag.size.height);
    canvas.drawPicture(flag.picture);
    canvas.restore();
  }

  void _morePill(Canvas canvas, int n, double right, double centreY) {
    final label = '+$n';
    final w = 16 + label.length * 8.5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(right - w, centreY - 13, w, 26),
      const Radius.circular(13),
    );
    canvas.drawRRect(rect, Paint()..color = palette.highlight);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ArtInk.white,
    );
    final tp = TextPainter(
      text: TextSpan(text: label, style: AppType.artBadge.copyWith(color: palette.onHighlight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(right - w / 2 - tp.width / 2, centreY - tp.height / 2));
  }

  @override
  bool shouldRepaint(PackArtPainter old) =>
      old.palette.bgTop != palette.bgTop ||
      old.palette.highlight != palette.highlight ||
      old.current != current ||
      !_sameCodes(old.codes, codes) ||
      old.flags.length != flags.length;

  static bool _sameCodes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

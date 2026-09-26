/// Regenerates `lib/core/i18n/country_shapes.g.dart`: one normalised outline
/// per country, so a card can draw the destination's actual shape.
///
/// ```
/// dart run tool/gen_country_shapes.dart
/// ```
///
/// Source: Natural Earth 1:110m Admin 0 (public domain), via the
/// natural-earth-vector mirror. Fetched rather than vendored for the same
/// reason `gen_place_names.dart` fetches CLDR — the dataset is an input to the
/// build, not a thing this repo maintains.
///
/// Three decisions worth keeping if this is ever rewritten:
///
///  * **Only the mainland.** Rings smaller than 6% of a country's largest ring
///    are dropped, so France is France rather than France plus a scatter of
///    overseas dots that would shrink the recognisable part to nothing.
///  * **Longitude is scaled by cos(latitude).** Raw lon/lat drawn as x/y
///    stretches everything away from the equator — Norway comes out twice its
///    width. One cosine at the shape's mean latitude fixes the proportions
///    well enough at card size, without pulling in a projection library.
///  * **Simplified relative to each country's own size**, not in absolute
///    degrees. An absolute tolerance keeps Russia and flattens Austria into a
///    triangle; a relative one gives both the same amount of character.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _source =
    'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson';

/// Douglas–Peucker tolerance, as a fraction of the shape's bounding diagonal.
const double _tolerance = 0.006;

/// Rings smaller than this fraction of the biggest one are islands, not the
/// country's silhouette.
const double _minRingArea = 0.06;

/// How far from the main landmass a ring may sit, as a multiple of that
/// landmass's own bounding diagonal, before it counts as overseas.
const double _maxRingDistance = 1.2;

typedef P = List<double>;

double _ringArea(List<P> r) {
  var s = 0.0;
  for (var i = 0; i < r.length - 1; i++) {
    s += r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1];
  }
  return s.abs() / 2;
}

/// The mean of a ring's vertices. Good enough to tell "next door" from
/// "another continent", which is all it is used for.
P _centroid(List<P> r) {
  var x = 0.0, y = 0.0;
  for (final p in r) {
    x += p[0];
    y += p[1];
  }
  return <double>[x / r.length, y / r.length];
}

double _diagonal(List<P> r) {
  final xs = r.map((p) => p[0]);
  final ys = r.map((p) => p[1]);
  final w = xs.reduce(math.max) - xs.reduce(math.min);
  final h = ys.reduce(math.max) - ys.reduce(math.min);
  return math.sqrt(w * w + h * h);
}

List<P> _rdp(List<P> pts, double eps) {
  if (pts.length < 3) return pts;
  final a = pts.first, b = pts.last;
  final den = math.sqrt(math.pow(b[1] - a[1], 2) + math.pow(b[0] - a[0], 2));
  var dmax = 0.0, idx = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final p = pts[i];
    // A closed ring's first and last point coincide, which makes the
    // perpendicular distance zero for EVERY vertex and collapses the whole
    // outline to a two-point line. Fall back to radial distance there.
    final d = den < 1e-12
        ? math.sqrt(math.pow(p[0] - a[0], 2) + math.pow(p[1] - a[1], 2))
        : ((b[1] - a[1]) * p[0] - (b[0] - a[0]) * p[1] + b[0] * a[1] - b[1] * a[0]).abs() / den;
    if (d > dmax) {
      dmax = d;
      idx = i;
    }
  }
  if (dmax > eps) {
    final left = _rdp(pts.sublist(0, idx + 1), eps);
    return <P>[...left.sublist(0, left.length - 1), ..._rdp(pts.sublist(idx), eps)];
  }
  return <P>[a, b];
}

/// Simplifies a closed ring by splitting it at its farthest vertex first, so
/// the degenerate first-equals-last case never reaches [_rdp] as one chain.
List<P> _simplifyRing(List<P> ring, double eps) {
  final open = (ring.first[0] == ring.last[0] && ring.first[1] == ring.last[1])
      ? ring.sublist(0, ring.length - 1)
      : ring;
  if (open.length < 4) return ring;
  final a = open.first;
  var m = 1;
  var best = -1.0;
  for (var i = 1; i < open.length; i++) {
    final d = math.pow(open[i][0] - a[0], 2) + math.pow(open[i][1] - a[1], 2);
    if (d > best) {
      best = d.toDouble();
      m = i;
    }
  }
  final head = _rdp(open.sublist(0, m + 1), eps);
  final tail = _rdp(<P>[...open.sublist(m), a], eps);
  return <P>[...head.sublist(0, head.length - 1), ...tail];
}

Future<String> _fetch(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw StateError('$url -> HTTP ${res.statusCode}');
    }
    // Awaited inside the try, so `finally` cannot close the client out from
    // under a stream that has not finished draining.
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> main() async {
  stdout.writeln('fetching Natural Earth 110m…');
  final geo = jsonDecode(await _fetch(_source)) as Map<String, dynamic>;
  final features = geo['features'] as List<dynamic>;

  final shapes = <String, String>{};
  final aspects = <String, double>{};

  for (final raw in features) {
    final f = raw as Map<String, dynamic>;
    final props = f['properties'] as Map<String, dynamic>;
    // ISO_A2_EH first. Natural Earth codes a handful of countries — France
    // and Norway among them — as `-99` in ISO_A2 for sovereignty reasons and
    // puts the real code only in the _EH ("de facto") variant. Reading the
    // plain field silently dropped both, which showed up as France having no
    // outline on a screen whose whole point is the outline.
    final iso = ((props['ISO_A2_EH'] as String?)?.trim().isNotEmpty ?? false
            ? props['ISO_A2_EH'] as String
            : (props['ISO_A2'] as String? ?? ''))
        .toLowerCase();
    if (iso.length != 2 || iso.startsWith('-')) continue;

    final g = f['geometry'] as Map<String, dynamic>;
    final coords = g['coordinates'] as List<dynamic>;
    final polys = g['type'] == 'MultiPolygon' ? coords : <dynamic>[coords];

    var rings = <List<P>>[
      for (final p in polys)
        [
          // JSON gives whole-number coordinates as int, so `as double` throws
          // on the one country whose border happens to land on a round degree.
          for (final pt in (p as List<dynamic>).first as List<dynamic>)
            <double>[
              ((pt as List<dynamic>)[0] as num).toDouble(),
              (pt[1] as num).toDouble(),
            ],
        ],
    ];
    if (rings.isEmpty) continue;

    final biggest = rings.map(_ringArea).reduce(math.max);
    rings = rings.where((r) => _ringArea(r) >= biggest * _minRingArea).toList();

    // ...and then drop what is merely far away. Natural Earth files overseas
    // territory under its sovereign: France carries French Guiana, which is
    // 15% of the mainland's area and so survives the size filter above. The
    // bounding box then stretched from South America to Europe and drew
    // France as a four-pixel speck. A card wants the landmass the name means.
    final main = rings.reduce((a, b) => _ringArea(a) >= _ringArea(b) ? a : b);
    final mc = _centroid(main);
    final reach = _diagonal(main) * _maxRingDistance;
    rings = rings.where((r) {
      final c = _centroid(r);
      return math.sqrt(math.pow(c[0] - mc[0], 2) + math.pow(c[1] - mc[1], 2)) <= reach;
    }).toList();

    // Equirectangular with a cosine correction at the shape's own latitude.
    final lats = <double>[for (final r in rings) for (final p in r) p[1]];
    final meanLat = lats.reduce((a, b) => a + b) / lats.length;
    final k = math.cos(meanLat * math.pi / 180).abs().clamp(0.15, 1.0);
    final projected = <List<P>>[
      for (final r in rings) [for (final p in r) <double>[p[0] * k, -p[1]]],
    ];

    final xs = <double>[for (final r in projected) for (final p in r) p[0]];
    final ys = <double>[for (final r in projected) for (final p in r) p[1]];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final w = (maxX - minX).abs(), h = (maxY - minY).abs();
    final span = math.max(w, h);
    if (span <= 0) continue;
    final eps = math.sqrt(w * w + h * h) * _tolerance;

    final buf = StringBuffer();
    for (final r in projected) {
      final s = _simplifyRing(r, eps);
      if (s.length < 3) continue;
      for (var i = 0; i < s.length; i++) {
        // Normalised into 0..1 on the LONGER axis, centred on the other, so a
        // painter can scale by one number and keep the proportions.
        final x = (s[i][0] - minX) / span + (span - w) / (2 * span);
        final y = (s[i][1] - minY) / span + (span - h) / (2 * span);
        buf.write(i == 0 ? 'M' : 'L');
        buf.write('${x.toStringAsFixed(3)} ${y.toStringAsFixed(3)}');
      }
      buf.write('Z');
    }
    if (buf.isEmpty) continue;
    shapes[iso] = buf.toString();
    aspects[iso] = w / h;
  }

  final keys = shapes.keys.toList()..sort();
  final out = StringBuffer(_header)
    ..writeln('const Map<String, String> kCountryShapes = <String, String>{');
  for (final k in keys) {
    out.writeln("  '$k': '${shapes[k]}',");
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln('/// Width divided by height, for a painter that must not stretch a country.')
    ..writeln('const Map<String, double> kCountryAspect = <String, double>{');
  for (final k in keys) {
    out.writeln("  '$k': ${aspects[k]!.toStringAsFixed(3)},");
  }
  out.writeln('};');

  final file = File('lib/core/i18n/country_shapes.g.dart');
  file.writeAsStringSync(out.toString());
  final kb = (file.lengthSync() / 1024).toStringAsFixed(0);
  stdout.writeln('${keys.length} country outlines ($kb KB) -> ${file.path}');
}

const _header = '''
/// One normalised outline per country, for the destination cards.
///
/// GENERATED — `dart run tool/gen_country_shapes.dart`. Do not edit by hand.
///
/// Each value is an SVG-ish path in a 0..1 box: `M`/`L` pairs and `Z` per
/// ring, already simplified, already corrected for latitude stretch, and
/// already centred on its shorter axis. A painter scales by one number.
///
/// Source: Natural Earth 1:110m Admin 0, public domain. Coverage is 171 of
/// the catalogue's ~200 destinations — small states and territories have no
/// outline at this resolution, and those cards fall back to the colour swell.
library;

''';

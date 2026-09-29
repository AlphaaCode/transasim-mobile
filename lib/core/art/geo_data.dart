/// The geometry behind the pack art: `assets/pack_art/geo.json`.
///
/// Produced by the web team's `build-pack-art.mjs` from Natural Earth via
/// world-atlas (public domain / ISC). 236 country silhouettes already
/// projected into a 200x150 frame, 236 lon/lat outlines for the zone and globe
/// maps, and 4 unnamed territories that only ever appear as background land.
///
/// Loaded once and held: it is 1.1 MB of JSON and the parse is not free, but
/// it never changes for the life of the process.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Path;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_drawing/path_drawing.dart';

import 'geo_projection.dart';

/// A country's silhouette, pre-projected into the 200x150 frame.
class CountryShape {
  /// SVG path data, already in frame coordinates.
  final String d;

  /// `[x, y, w, h]` bounding box of [d].
  final List<double> box;

  /// How much of [box] the country actually fills, 0–1. Below 0.05 the shape
  /// is too thin to read and the waving-flag fallback is used instead.
  final double fill;

  const CountryShape({required this.d, required this.box, required this.fill});

  double get x => box[0];
  double get y => box[1];
  double get w => box[2];
  double get h => box[3];
}

/// A country as the zone and globe maps need it.
class CountryGeo {
  /// Centre of the main landmass, (lon, lat).
  final LonLat centre;

  /// Area of the main landmass in steradians — ranks which flags to pin.
  final double area;

  /// ~24 outline points, used only for framing a zone.
  final List<LonLat> outline;

  /// Polygon rings in lon/lat, to draw.
  final List<List<LonLat>> rings;

  const CountryGeo({
    required this.centre,
    required this.area,
    required this.outline,
    required this.rings,
  });
}

class GeoData {
  final Map<String, CountryShape> shapes;
  final Map<String, CountryGeo> countries;

  /// Territories with no ISO code — Northern Cyprus and friends. Background
  /// land only: never covered, never pinned.
  final List<List<List<LonLat>>> others;

  GeoData({required this.shapes, required this.countries, required this.others});

  static GeoData? _cache;
  static Future<GeoData>? _loading;

  /// The parsed data, loaded at most once per process.
  static Future<GeoData> load() {
    final hit = _cache;
    if (hit != null) return Future.value(hit);
    return _loading ??= rootBundle.loadString('assets/pack_art/geo.json').then((raw) {
      final data = _parse(jsonDecode(raw) as Map<String, dynamic>);
      _cache = data;
      _loading = null;
      return data;
    });
  }

  /// Non-null once [load] has completed — lets a painter stay synchronous.
  static GeoData? get cached => _cache;

  static GeoData _parse(Map<String, dynamic> json) {
    final shapes = <String, CountryShape>{};
    (json['shapes'] as Map<String, dynamic>).forEach((code, raw) {
      final s = raw as Map<String, dynamic>;
      shapes[code] = CountryShape(
        d: s['d'] as String,
        box: [for (final v in s['box'] as List<dynamic>) (v as num).toDouble()],
        fill: (s['fill'] as num).toDouble(),
      );
    });

    final countries = <String, CountryGeo>{};
    (json['countries'] as Map<String, dynamic>).forEach((code, raw) {
      final c = raw as Map<String, dynamic>;
      final centre = c['c'] as List<dynamic>;
      countries[code] = CountryGeo(
        centre: ((centre[0] as num).toDouble(), (centre[1] as num).toDouble()),
        area: (c['a'] as num).toDouble(),
        outline: [
          for (final p in c['s'] as List<dynamic>)
            (((p as List<dynamic>)[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        rings: _rings(c['g'] as Map<String, dynamic>),
      );
    });

    final others = <List<List<LonLat>>>[
      for (final g in json['others'] as List<dynamic>) _rings(g as Map<String, dynamic>),
    ];

    return GeoData(shapes: shapes, countries: countries, others: others);
  }

  /// GeoJSON Polygon / MultiPolygon to a flat list of rings.
  ///
  /// Holes are kept as rings of their own: at this size an even-odd fill
  /// renders Lesotho inside South Africa correctly and costs nothing.
  static List<List<LonLat>> _rings(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String;
    final coords = geometry['coordinates'] as List<dynamic>;
    final out = <List<LonLat>>[];
    void addRing(List<dynamic> ring) {
      out.add([
        for (final p in ring)
          (((p as List<dynamic>)[0] as num).toDouble(), (p[1] as num).toDouble()),
      ]);
    }

    if (type == 'Polygon') {
      for (final ring in coords) {
        addRing(ring as List<dynamic>);
      }
    } else if (type == 'MultiPolygon') {
      for (final poly in coords) {
        for (final ring in poly as List<dynamic>) {
          addRing(ring as List<dynamic>);
        }
      }
    }
    return out;
  }

  /// The silhouette's path, parsed and cached.
  Path? shapePath(String code) {
    final hit = _paths[code];
    if (hit != null) return hit;
    final s = shapes[code];
    if (s == null) return null;
    return _paths[code] = parseSvgPathData(s.d);
  }

  /// Parsed silhouettes, kept because `parseSvgPathData` on a 6 KB path is not
  /// something a scrolling list should do twice.
  final Map<String, Path> _paths = <String, Path>{};
}

/// Whether a coverage reads as a region or the whole world, from geography
/// alone — `classifyCoverage` in art.ts.
///
/// No list of zones to maintain: 90% of the covered countries within 65 deg of
/// the coverage's own centre is a region, anything wider is the globe. On the
/// real catalogue the world packs measure 94 deg and the zones 7–45 deg, so
/// the threshold is not near anything.
class Coverage {
  final bool isWorld;
  final LonLat centre;

  /// The codes that exist in the geo data. Unknown codes still count toward
  /// the "+N" pill but cannot be drawn.
  final List<String> known;

  final double spreadDegrees;

  const Coverage({
    required this.isWorld,
    required this.centre,
    required this.known,
    required this.spreadDegrees,
  });

  static Coverage classify(List<String> codes, Map<String, CountryGeo> countries) {
    final known = [for (final c in codes) if (countries.containsKey(c)) c];
    if (known.isEmpty) {
      return const Coverage(isWorld: false, centre: (0, 0), known: [], spreadDegrees: 0);
    }
    final centre = sphericalMean([for (final c in known) countries[c]!.centre]);
    final spread = quantileAt(
      [for (final c in known) geoDistance(countries[c]!.centre, centre) * 180 / math.pi],
      0.9,
    );
    return Coverage(
      isWorld: spread > 65,
      centre: centre,
      known: known,
      spreadDegrees: spread,
    );
  }
}

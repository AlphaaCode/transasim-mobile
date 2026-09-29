/// The slice of d3-geo the pack art actually needs, written out.
///
/// The web renderer leans on `d3-geo` for rotation, two projections, angular
/// distance and `fitExtent`. Dart has no mature equivalent, but the formulas
/// are short and are spelled out in LISEZMOI §5, so they are here rather than
/// as a dependency. Every function below has a named counterpart in d3 so the
/// two can be compared when something looks wrong.
library;

import 'dart:math' as math;

const double _deg = math.pi / 180;

/// A longitude/latitude pair in degrees, as the geo data stores them.
typedef LonLat = (double, double);

/// Rotates the globe so that [centre] sits at the origin — `d3.geoRotation`
/// with `[-lambda0, -phi0]`.
class GeoRotation {
  final double _lambda0;
  final double _cosPhi0;
  final double _sinPhi0;

  GeoRotation(LonLat centre)
      : _lambda0 = centre.$1 * _deg,
        _cosPhi0 = math.cos(centre.$2 * _deg),
        _sinPhi0 = math.sin(centre.$2 * _deg);

  /// Returns the rotated (lambda, phi) in RADIANS.
  (double, double) call(LonLat p) {
    var lambda = p.$1 * _deg - _lambda0;
    // Back into [-pi, pi]; a zone straddling the antimeridian otherwise
    // projects to the far side of the map.
    while (lambda > math.pi) {
      lambda -= 2 * math.pi;
    }
    while (lambda < -math.pi) {
      lambda += 2 * math.pi;
    }
    final phi = p.$2 * _deg;
    final cosPhi = math.cos(phi);
    final x = cosPhi * math.cos(lambda);
    final y = cosPhi * math.sin(lambda);
    final z = math.sin(phi);
    return (
      math.atan2(y, x * _cosPhi0 + z * _sinPhi0),
      math.asin((z * _cosPhi0 - x * _sinPhi0).clamp(-1.0, 1.0)),
    );
  }
}

/// Great-circle angular distance in radians — `d3.geoDistance`.
double geoDistance(LonLat a, LonLat b) {
  final phi1 = a.$2 * _deg, phi2 = b.$2 * _deg;
  final dLambda = (b.$1 - a.$1) * _deg;
  final x = math.sin(phi1) * math.sin(phi2) +
      math.cos(phi1) * math.cos(phi2) * math.cos(dLambda);
  return math.acos(x.clamp(-1.0, 1.0));
}

/// The unit-vector mean of a set of points, back in degrees.
///
/// A plain average of longitudes puts the centre of a Pacific-spanning zone in
/// Africa; this does not.
LonLat sphericalMean(Iterable<LonLat> points) {
  var x = 0.0, y = 0.0, z = 0.0;
  for (final p in points) {
    final lon = p.$1 * _deg, lat = p.$2 * _deg;
    x += math.cos(lat) * math.cos(lon);
    y += math.cos(lat) * math.sin(lon);
    z += math.sin(lat);
  }
  return (
    math.atan2(y, x) / _deg,
    math.atan2(z, math.sqrt(x * x + y * y)) / _deg,
  );
}

/// The quantile d3 and art.ts use: sort, then index `round(q * (n - 1))`.
double quantileAt(List<double> values, double q) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  final i = (q * (s.length - 1)).round().clamp(0, s.length - 1);
  return s[i];
}

/// A projection: rotate, project to the unit plane, then scale and translate.
abstract class GeoProjection {
  final GeoRotation rotation;
  double scale;
  double tx;
  double ty;

  GeoProjection(LonLat centre, {this.scale = 1, this.tx = 0, this.ty = 0})
      : rotation = GeoRotation(centre);

  /// The raw projection, before scale and translation. Null when the point is
  /// not visible in this projection (the far side of an orthographic globe).
  (double, double)? raw(double lambda, double phi);

  /// Screen position, or null when hidden. `y` is negated because the raw
  /// projections use mathematical axes and the canvas does not.
  math.Point<double>? project(LonLat p) {
    final r = rotation(p);
    final xy = raw(r.$1, r.$2);
    if (xy == null) return null;
    return math.Point(tx + scale * xy.$1, ty - scale * xy.$2);
  }

  /// Whether the point is on the visible face at all.
  bool visible(LonLat p) {
    final r = rotation(p);
    return raw(r.$1, r.$2) != null;
  }

  /// Scales and translates so [points] fill [rect] — `projection.fitExtent`.
  void fitExtent(List<LonLat> points, double x0, double y0, double x1, double y1) {
    scale = 1;
    tx = 0;
    ty = 0;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      final q = project(p);
      if (q == null) continue;
      minX = math.min(minX, q.x);
      maxX = math.max(maxX, q.x);
      minY = math.min(minY, q.y);
      maxY = math.max(maxY, q.y);
    }
    if (minX > maxX) return;
    final dx = maxX - minX, dy = maxY - minY;
    final s = math.min(
      dx == 0 ? double.infinity : (x1 - x0) / dx,
      dy == 0 ? double.infinity : (y1 - y0) / dy,
    );
    if (!s.isFinite) return;
    scale = s;
    tx = x0 + ((x1 - x0) - s * (maxX + minX)) / 2;
    ty = y0 + ((y1 - y0) - s * (maxY + minY)) / 2;
  }
}

/// Lambert azimuthal equal-area — the zone maps.
class AzimuthalEqualAreaProjection extends GeoProjection {
  AzimuthalEqualAreaProjection(super.centre);

  @override
  (double, double)? raw(double lambda, double phi) {
    final cosPhi = math.cos(phi);
    final denominator = 1 + cosPhi * math.cos(lambda);
    // The antipode of the centre, where the projection is undefined.
    if (denominator <= 1e-9) return null;
    final k = math.sqrt(2 / denominator);
    return (k * cosPhi * math.sin(lambda), k * math.sin(phi));
  }
}

/// Orthographic — the globe. Only the near hemisphere exists.
class OrthographicProjection extends GeoProjection {
  OrthographicProjection(super.centre, {super.scale, super.tx, super.ty});

  @override
  (double, double)? raw(double lambda, double phi) {
    final cosPhi = math.cos(phi);
    if (cosPhi * math.cos(lambda) <= 0) return null;
    return (cosPhi * math.sin(lambda), math.sin(phi));
  }

  /// A hidden point pushed out to the horizon, so a polygon straddling the
  /// limb closes along the edge instead of tearing across the globe.
  ///
  /// LISEZMOI §5.4 suggests exactly this in place of d3's proper clipping:
  /// at 96px radius the difference is not visible.
  math.Point<double> projectClamped(LonLat p) {
    final r = rotation(p);
    final cosPhi = math.cos(r.$2);
    var x = cosPhi * math.sin(r.$1);
    var y = math.sin(r.$2);
    if (cosPhi * math.cos(r.$1) <= 0) {
      final len = math.sqrt(x * x + y * y);
      if (len > 1e-9) {
        x /= len;
        y /= len;
      }
    }
    return math.Point(tx + scale * x, ty - scale * y);
  }
}

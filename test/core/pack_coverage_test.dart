import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/art/geo_data.dart';
import 'package:transasim_mobile/core/art/geo_projection.dart';

/// Zone-versus-world classification, against the nine real coverages the web
/// team measured (`couvertures-reelles.json`).
///
/// This is the one decision in the pack art with no list behind it: geography
/// alone picks the rendering. LISEZMOI §4.5 records what the real catalogue
/// measures — the world packs at 94 deg, the zones between 7 and 45 — so the
/// 65 deg threshold has a wide margin on both sides. That margin is what this
/// test protects: a regression would show up as a zone drifting past 65, long
/// before anyone saw a globe on a Europe pack.
void main() {
  late Map<String, CountryGeo> countries;
  late Map<String, dynamic> real;

  setUpAll(() {
    final geo = File('assets/pack_art/geo.json');
    final raw = jsonDecode(geo.readAsStringSync()) as Map<String, dynamic>;
    countries = <String, CountryGeo>{};
    (raw['countries'] as Map<String, dynamic>).forEach((code, v) {
      final c = v as Map<String, dynamic>;
      final centre = c['c'] as List<dynamic>;
      countries[code] = CountryGeo(
        centre: ((centre[0] as num).toDouble(), (centre[1] as num).toDouble()),
        area: (c['a'] as num).toDouble(),
        outline: const [],
        rings: const [],
      );
    });

    final fixture = File(r'C:\Users\akaro\Downloads\flutter-fond-forfaits'
        r'\flutter-fond-forfaits\exemples\couvertures-reelles.json');
    real = fixture.existsSync()
        ? jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
  });

  test('the geo data carries every country the maps need', () {
    expect(countries.length, 236);
  });

  test('every real coverage classifies, and the spreads match the documented range', () {
    if (real.isEmpty) {
      markTestSkipped('reference package not on this machine');
      return;
    }
    final spreads = <String, double>{};
    real.forEach((key, raw) {
      final entry = raw as Map<String, dynamic>;
      final codes = [for (final c in entry['codes'] as List<dynamic>) c as String];
      final cov = Coverage.classify(codes, countries);
      spreads[key] = cov.spreadDegrees;

      expect(cov.known, isNotEmpty, reason: '$key resolved no countries at all');
      // Every real pack must land clear of the boundary, either way.
      expect((cov.spreadDegrees - 65).abs(), greaterThan(5),
          reason: '$key sits at ${cov.spreadDegrees.toStringAsFixed(1)} deg, '
              'too close to the 65 deg threshold to be safe');
    });

    // The shapes the catalogue actually has: tight regional packs and a
    // genuinely global one.
    final worlds = spreads.entries.where((e) => e.value > 65).toList();
    final zones = spreads.entries.where((e) => e.value <= 65).toList();
    expect(zones, isNotEmpty, reason: 'no coverage classified as a zone');
    expect(worlds, isNotEmpty, reason: 'no coverage classified as world');
    for (final z in zones) {
      // LISEZMOI says "entre 7 et 45"; the Americas pack actually measures
      // 45.05, so the prose is the rounded figure. The bound here is the
      // claim that matters — every zone stays well short of the threshold.
      expect(z.value, lessThan(50.0),
          reason: '${z.key} is a zone but spreads ${z.value.toStringAsFixed(1)} deg; '
              'LISEZMOI records zones at 7-45');
    }
    for (final w in worlds) {
      expect(w.value, greaterThan(80.0), reason: '${w.key} claims world at only ${w.value}');
    }
  });

  test('an unknown code is ignored for drawing but still exists to be counted', () {
    final cov = Coverage.classify(['FRA', 'ZZZ', 'DEU'], countries);
    expect(cov.known, ['FRA', 'DEU']);
  });

  test('a coverage with nothing known does not divide by zero', () {
    final cov = Coverage.classify(['ZZZ'], countries);
    expect(cov.known, isEmpty);
    expect(cov.isWorld, isFalse);
  });

  group('projection maths', () {
    test('rotation brings its own centre to the origin', () {
      final r = GeoRotation((2.46, 46.57));
      final o = r((2.46, 46.57));
      expect(o.$1, closeTo(0, 1e-9));
      expect(o.$2, closeTo(0, 1e-9));
    });

    test('rotation takes the short way across the antimeridian', () {
      final r = GeoRotation((179.0, 0));
      final o = r((-179.0, 0)); // 2 deg east, not 358 deg west
      expect(o.$1 * 180 / math.pi, closeTo(2.0, 1e-6));
    });

    test('great-circle distance: a quarter turn is 90 degrees', () {
      expect(geoDistance((0, 0), (90, 0)) * 180 / math.pi, closeTo(90, 1e-9));
      expect(geoDistance((0, 0), (0, 0)), closeTo(0, 1e-12));
    });

    test('spherical mean does not put a Pacific pair in Africa', () {
      // The trap a plain average of longitudes falls into: (170 + -170)/2 = 0.
      final m = sphericalMean(const [(170.0, 0.0), (-170.0, 0.0)]);
      expect(m.$1.abs(), closeTo(180, 1e-6));
      expect(m.$2, closeTo(0, 1e-9));
    });

    test('the orthographic globe hides the far side', () {
      final p = OrthographicProjection((0, 0));
      expect(p.visible((0, 0)), isTrue);
      expect(p.visible((180, 0)), isFalse);
    });

    test('fitExtent puts the points inside the box it was given', () {
      final p = AzimuthalEqualAreaProjection((10, 50));
      final pts = <LonLat>[(0, 45), (20, 55), (5, 48), (15, 52)];
      p.fitExtent(pts, 40, 34, 360, 209);
      for (final q in pts) {
        final xy = p.project(q)!;
        expect(xy.x, inInclusiveRange(39.9, 360.1));
        expect(xy.y, inInclusiveRange(33.9, 209.1));
      }
    });
  });
}

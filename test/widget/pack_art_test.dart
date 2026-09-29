@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/art/geo_data.dart';
import 'package:transasim_mobile/core/art/pack_art_painter.dart';
import 'package:transasim_mobile/core/art/pack_palette.dart';

import 'real_fonts.dart';

/// The pack art, rendered at the reference frame so it can be put beside the
/// web team's own SVGs (`exemples/<marque>/`, all 400x225).
///
/// Regenerate:
///   flutter test --update-goldens test/widget/pack_art_test.dart
///
/// The goldens here are the app's output. Comparing them to the reference is
/// done by eye against `exemples/`, which is what the transmission package
/// asks for — a pixel-exact match is not achievable, because the web draws
/// through an SVG filter chain and this draws through Skia. What must match is
/// the composition: same framing, same colours, same pins, same "+N".

const _sabily = (primary: Color(0xFF21564F), accent: Color(0xFF55B576), cta: Color(0xFFD8B708));
const _esimple = (primary: Color(0xFF49CDD2), accent: Color(0xFF3B82F6), cta: Color(0xFF2F3B4F));

Future<GeoData> _geo() async {
  final raw = File('assets/pack_art/geo.json').readAsStringSync();
  // The painter's own loader goes through rootBundle, which a plain unit test
  // has no asset for; parsing the file directly keeps this test honest about
  // using the SAME data the app ships.
  return _parse(jsonDecode(raw) as Map<String, dynamic>);
}

GeoData _parse(Map<String, dynamic> json) {
  final shapes = <String, CountryShape>{};
  (json['shapes'] as Map<String, dynamic>).forEach((code, raw) {
    final s = raw as Map<String, dynamic>;
    shapes[code] = CountryShape(
      d: s['d'] as String,
      box: [for (final v in s['box'] as List<dynamic>) (v as num).toDouble()],
      fill: (s['fill'] as num).toDouble(),
    );
  });
  List<List<(double, double)>> rings(Map<String, dynamic> g) {
    final out = <List<(double, double)>>[];
    void add(List<dynamic> r) => out.add([
          for (final p in r)
            (((p as List<dynamic>)[0] as num).toDouble(), (p[1] as num).toDouble()),
        ]);
    final c = g['coordinates'] as List<dynamic>;
    if (g['type'] == 'Polygon') {
      for (final r in c) {
        add(r as List<dynamic>);
      }
    } else {
      for (final poly in c) {
        for (final r in poly as List<dynamic>) {
          add(r as List<dynamic>);
        }
      }
    }
    return out;
  }

  final countries = <String, CountryGeo>{};
  (json['countries'] as Map<String, dynamic>).forEach((code, raw) {
    final c = raw as Map<String, dynamic>;
    final ctr = c['c'] as List<dynamic>;
    countries[code] = CountryGeo(
      centre: ((ctr[0] as num).toDouble(), (ctr[1] as num).toDouble()),
      area: (c['a'] as num).toDouble(),
      outline: [
        for (final p in c['s'] as List<dynamic>)
          (((p as List<dynamic>)[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
      rings: rings(c['g'] as Map<String, dynamic>),
    );
  });
  return GeoData(
    shapes: shapes,
    countries: countries,
    others: [for (final g in json['others'] as List<dynamic>) rings(g as Map<String, dynamic>)],
  );
}

Future<Map<String, PackFlag>> _flags(Iterable<String> codes) async {
  final out = <String, PackFlag>{};
  for (final code in codes) {
    final file = File('assets/pack_art/flags/$code.svg');
    if (!file.existsSync()) continue;
    final info = await vg.loadPicture(SvgStringLoader(file.readAsStringSync()), null);
    out[code] = PackFlag(info.picture, info.size);
  }
  return out;
}

/// Paints the art into a widget of exactly the reference size.
Widget _frame(PackArtPainter painter) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: kArtWidth,
          height: kArtHeight,
          child: CustomPaint(painter: painter, size: const Size(kArtWidth, kArtHeight)),
        ),
      ),
    );

void main() {
  late GeoData geo;
  setUpAll(() async {
    // Without this the "+N" badge records as Ahem boxes and the golden goes
    // green on a picture of tofu — the exact trap real_fonts.dart documents.
    await loadRealFonts();
    geo = await _geo();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    ({Color primary, Color accent, Color cta}) brand,
    List<String> codes, {
    String? current,
    Iterable<String>? flagCodes,
  }) async {
    final flags = await _flags(flagCodes ?? codes);
    await tester.pumpWidget(_frame(PackArtPainter(
      palette: PackPalette.of(brand.primary, brand.accent, brand.cta),
      geo: geo,
      codes: codes,
      current: current,
      flags: flags,
    )));
    await expectLater(
      find.byType(CustomPaint).last,
      matchesGoldenFile('goldens/art_$name.png'),
    );
  }

  group('one country', () {
    testWidgets('FRA, Sabily', (t) => shoot(t, 'sabily_FRA', _sabily, ['FRA']));
    testWidgets('JPN, Sabily', (t) => shoot(t, 'sabily_JPN', _sabily, ['JPN']));
    testWidgets('USA, Sabily', (t) => shoot(t, 'sabily_USA', _sabily, ['USA']));
    testWidgets('MLT, Sabily — a very small country', (t) => shoot(t, 'sabily_MLT', _sabily, ['MLT']));
    testWidgets('REU, Sabily — no silhouette, waving-flag fallback',
        (t) => shoot(t, 'sabily_REU', _sabily, ['REU']));
    testWidgets('FRA, eSimple — the light tone', (t) => shoot(t, 'esimple_FRA', _esimple, ['FRA']));

    // AND's flag declares its colours in a <style> block and applies them with
    // class="F". flutter_svg does not implement CSS, so before
    // tool/inline_flag_css.py ran, Andorra's yellow band painted BLACK — on
    // the card and in the badge beside it. Nine flags are built that way;
    // this golden is the one that would catch them coming back.
    testWidgets('AND — a flag whose colours came from CSS classes',
        (t) => shoot(t, 'sabily_AND', _sabily, ['AND']));
  });

  group('zone and world', () {
    const eur = [
      'LVA', 'AND', 'LTU', 'LUX', 'HUN', 'POL', 'AUT', 'HRV', 'MLT', 'PRT', 'CYP', 'GBR',
      'CZE', 'ROU', 'DNK', 'UKR', 'BEL', 'IRL', 'ITA', 'GIB', 'ESP', 'GGY', 'NLD', 'IMN',
      'JEY', 'EST', 'SVK', 'LIE', 'FIN', 'SVN', 'BGR', 'MDA', 'NOR', 'FRA', 'SWE', 'DEU',
      'CHE', 'GRC',
    ];
    const asi = [
      'LAO', 'TWN', 'CHN', 'PHL', 'TJK', 'THA', 'BGD', 'MYS', 'HKG', 'BRN', 'MAC', 'UZB',
      'IND', 'IDN', 'AZE', 'SGP', 'KAZ', 'KGZ', 'JPN', 'KOR', 'MNG', 'LKA', 'KHM', 'NPL',
      'PAK', 'VNM',
    ];
    // Deliberately spread across the globe, so this must classify as world.
    const wld = ['USA', 'BRA', 'ZAF', 'AUS', 'JPN', 'FRA', 'RUS', 'ARG', 'CAN', 'IND'];

    testWidgets('Europe, destination FRA', (t) => shoot(t, 'sabily_zone_EUR', _sabily, eur,
        current: 'FRA', flagCodes: const ['FRA', 'DEU', 'ESP', 'UKR', 'SWE', 'NOR', 'POL']));
    testWidgets('Asia, destination FRA (not covered)', (t) => shoot(t, 'sabily_zone_ASI', _sabily, asi,
        current: 'FRA', flagCodes: const ['CHN', 'IND', 'KAZ', 'IDN', 'MNG', 'PAK']));
    testWidgets('World, destination FRA', (t) => shoot(t, 'sabily_world', _sabily, wld,
        current: 'FRA', flagCodes: const ['FRA', 'USA', 'BRA', 'RUS', 'CAN', 'AUS']));
    testWidgets('Europe, eSimple', (t) => shoot(t, 'esimple_zone_EUR', _esimple, eur,
        current: 'FRA', flagCodes: const ['FRA', 'DEU', 'ESP', 'UKR', 'SWE', 'NOR', 'POL']));
  });

  test('the zone/world split is what the art actually branches on', () {
    // Guards the painter's own entry condition, not just the classifier.
    expect(Coverage.classify(const ['FRA'], geo.countries).known, ['FRA']);
    final world = Coverage.classify(
        const ['USA', 'BRA', 'ZAF', 'AUS', 'JPN', 'FRA', 'RUS'], geo.countries);
    expect(world.isWorld, isTrue);
    final europe = Coverage.classify(const ['FRA', 'DEU', 'ESP', 'ITA'], geo.countries);
    expect(europe.isWorld, isFalse);
  });
}

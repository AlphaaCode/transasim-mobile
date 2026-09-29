import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/art/pack_palette.dart';

/// The pack-art palette against the web team's own expected values.
///
/// `palettes-attendues.json` ships in the transmission package precisely so
/// this can be a unit test rather than a judgement call: if the app and the
/// site disagree on a single hex digit, the same brand gets two different
/// backgrounds on two surfaces, and nobody notices until a client does.
///
/// The inputs here are the fixture's, NOT this repo's brand.json — the test
/// pins the FORMULA. A brand changing its colours must not break it.
const _fixture = '''
{
  "sabily":  {"primary": "#21564F", "accent": "#55B576", "cta": "#D8B708",
              "bgTop": "#2e605a", "bgBottom": "#143531", "highlight": "#D8B708", "tone": "dark"},
  "esimple": {"primary": "#49CDD2", "accent": "#3B82F6", "cta": "#2F3B4F",
              "bgTop": "#e6f8f9", "bgBottom": "#ade9eb", "highlight": "#3B82F6", "tone": "light"},
  "acorn":   {"primary": "#234CDE", "accent": "#238ADE", "cta": "#FFB21E",
              "bgTop": "#3057e0", "bgBottom": "#162f8a", "highlight": "#FFB21E", "tone": "dark"}
}
''';

Color _hex(String h) => Color(int.parse(h.substring(1), radix: 16) | 0xFF000000);
String _str(Color c) => '#'
    '${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';

void main() {
  final brands = jsonDecode(_fixture) as Map<String, dynamic>;

  group('palette matches the web renderer exactly', () {
    brands.forEach((slug, raw) {
      final f = raw as Map<String, dynamic>;
      test(slug, () {
        final p = PackPalette.of(
          _hex(f['primary'] as String),
          _hex(f['accent'] as String),
          _hex(f['cta'] as String),
        );
        expect(p.tone.name, f['tone'], reason: 'tone');
        expect(_str(p.bgTop), (f['bgTop'] as String).toLowerCase(), reason: 'bgTop');
        expect(_str(p.bgBottom), (f['bgBottom'] as String).toLowerCase(), reason: 'bgBottom');
        expect(_str(p.highlight), (f['highlight'] as String).toLowerCase(), reason: 'highlight');
      });
    });

    test('the shipped fixture file still says what this test asserts', () {
      // Guards against the package being updated without the test following.
      final file = File(r'C:\Users\akaro\Downloads\flutter-fond-forfaits'
          r'\flutter-fond-forfaits\exemples\palettes-attendues.json');
      if (!file.existsSync()) return; // package not present on this machine
      final live = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final slug in brands.keys) {
        final expected = (live[slug] as Map<String, dynamic>)['attendu'] as Map<String, dynamic>;
        final mine = brands[slug] as Map<String, dynamic>;
        for (final key in ['bgTop', 'bgBottom', 'highlight']) {
          expect((mine[key] as String).toLowerCase(), (expected[key] as String).toLowerCase(),
              reason: '$slug.$key drifted from the shipped fixture');
        }
      }
    });
  });

  group('the pieces the palette is built from', () {
    test('mix rounds per channel, like the web', () {
      expect(_str(packMix(_hex('#000000'), _hex('#FFFFFF'), 0.5)), '#808080');
      expect(_str(packMix(_hex('#21564F'), _hex('#FFFFFF'), 0.06)), '#2e605a');
    });

    test('luminance splits the two tones at 0.22', () {
      expect(packLuminance(_hex('#49CDD2')), greaterThan(0.22));
      expect(packLuminance(_hex('#21564F')), lessThan(0.22));
      expect(packLuminance(_hex('#234CDE')), lessThan(0.22));
    });

    test('contrast is symmetric and 21:1 at the extremes', () {
      expect(packContrast(_hex('#FFFFFF'), _hex('#000000')), closeTo(21, 0.01));
      expect(packContrast(_hex('#000000'), _hex('#FFFFFF')), closeTo(21, 0.01));
    });

    test('saturation is zero on grey and one on a pure hue', () {
      expect(packSaturation(_hex('#808080')), 0);
      expect(packSaturation(_hex('#FF0000')), 1);
    });

    test('ensureContrast returns the colour untouched when it already passes', () {
      final c = _hex('#000000');
      expect(packEnsureContrast(c, _hex('#FFFFFF'), 3), c);
    });

    test('ensureContrast darkens toward black against a light ground', () {
      // Only reached when no brand colour clears 2:1, so it must still work.
      final out = packEnsureContrast(_hex('#CCCCCC'), _hex('#FFFFFF'), 3);
      expect(packContrast(out, _hex('#FFFFFF')), greaterThanOrEqualTo(3));
      expect(packLuminance(out), lessThan(packLuminance(_hex('#CCCCCC'))));
    });

    test('the +N label takes whichever of white/#111111 separates further', () {
      final sabily = PackPalette.of(_hex('#21564F'), _hex('#55B576'), _hex('#D8B708'));
      final esimple = PackPalette.of(_hex('#49CDD2'), _hex('#3B82F6'), _hex('#2F3B4F'));
      expect(_str(sabily.onHighlight), '#111111', reason: 'Sabily gold');

      // LISEZMOI §3.3 says "eSimple : blanc sur bleu", but the formula it
      // documents disagrees with its own prose: against highlight #3B82F6
      // (luminance 0.2355) white scores 3.68 and #111111 scores 5.13, so
      // art.ts picks #111111. The code is the contract, so this follows the
      // code — flagged to the web team rather than silently diverging.
      expect(_str(esimple.onHighlight), '#111111', reason: 'eSimple blue, per art.ts');
      expect(packContrast(esimple.onHighlight, esimple.highlight),
          greaterThan(packContrast(const Color(0xFFFFFFFF), esimple.highlight)));
    });
  });
}

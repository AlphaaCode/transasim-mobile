/// Regenerates `lib/core/i18n/country_colors.g.dart`: one identity colour per
/// country, derived from the flag this app already bundles.
///
/// ```
/// dart run tool/gen_country_colors.dart
/// ```
///
/// The colour belongs to the DESTINATION, not to the brand — Austria's card
/// reads red in every white-label app that ships this code. Everything else on
/// the card (text, button, pills) still comes from the brand's own tokens, so
/// there is no per-brand-per-country configuration anywhere and never can be:
/// this file is generated from `assets/flags/`, which is generated from the
/// catalogue's own country codes.
///
/// The heuristic is "first chromatic fill in document order". A flag's field
/// colour is painted before its charge, and near-white/near-black fills are
/// skipped because they are the paper, not the identity — which is why Austria
/// resolves red rather than white and Saudi Arabia green rather than white.
library;

import 'dart:io';

/// Saturation weighted against how close the colour is to white or black.
double _chroma(int r, int g, int b) {
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final mx = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
  final mn = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
  final l = (mx + mn) / 2;
  final d = mx - mn;
  final s = d == 0 ? 0.0 : d / (1 - (2 * l - 1).abs());
  return s * (1 - (l - 0.5).abs() * 1.2);
}

const _css = <String, String>{
  'red': 'ff0000', 'green': '008000', 'blue': '0000ff', 'black': '000000',
  'white': 'ffffff', 'yellow': 'ffff00', 'gold': 'ffd700', 'navy': '000080',
  'orange': 'ffa500',
};

int? _parse(String raw) {
  var c = raw.trim().toLowerCase();
  c = _css[c] ?? c;
  if (c.startsWith('#')) c = c.substring(1);
  if (c.length == 3) c = c.split('').map((ch) => '$ch$ch').join();
  if (c.length != 6) return null;
  return int.tryParse(c, radix: 16);
}

void main() {
  final files = Directory('assets/flags')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final out = StringBuffer();
  var resolved = 0;
  for (final f in files) {
    final code = f.uri.pathSegments.last.replaceAll('.svg', '');
    if (!RegExp(r'^[a-z]{2}$').hasMatch(code)) continue;
    final svg = f.readAsStringSync();
    final fills = RegExp(r'fill="([^"]+)"')
        .allMatches(svg)
        .map((m) => _parse(m.group(1)!))
        .whereType<int>()
        .toList();
    if (fills.isEmpty) continue;
    int pick = fills.firstWhere(
      (v) => _chroma((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF) > 0.25,
      orElse: () => fills.reduce((a, b) =>
          _chroma((a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF) >=
                  _chroma((b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF)
              ? a
              : b),
    );
    out.writeln("  '$code': 0xFF${pick.toRadixString(16).padLeft(6, '0').toUpperCase()},");
    resolved++;
  }

  File('lib/core/i18n/country_colors.g.dart').writeAsStringSync(
    '${_header}const Map<String, int> kCountryColors = <String, int>{\n$out};\n',
  );
  stdout.writeln('$resolved country colours -> lib/core/i18n/country_colors.g.dart');
}

const _header = '''
/// One identity colour per country, derived from its bundled flag.
///
/// GENERATED — `dart run tool/gen_country_colors.dart`. Do not edit by hand.
///
/// The colour is the DESTINATION's, not the brand's: Austria reads red in
/// every white-label app built from this code, while the text, button and
/// pills on the same card come from that brand's own tokens. Nothing here is
/// ever configured per brand.
library;

''';

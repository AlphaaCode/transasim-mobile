/// Regenerates `lib/core/i18n/country_flag_assets.g.dart` from whatever is
/// actually in `assets/pack_art/flags/` and `assets/flag_maps/`.
///
/// ```
/// dart run tool/gen_flag_codes.dart
/// ```
///
/// The flags come from the web team's pack-art transmission package, named by
/// ISO alpha-3 — the codes the backend actually sends — so no mapping stands
/// between a destination and its flag. The flag-maps are a separate, curated
/// set and are deliberately partial; they are named alpha-3 for the same
/// reason.
library;

import 'dart:io';

List<String> _codesIn(String dir, String extension) => Directory(dir)
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((n) => n.endsWith(extension))
    .map((n) => n.substring(0, n.length - extension.length))
    .where((c) => RegExp(r'^[A-Z]{3}$').hasMatch(c))
    .toList()
  ..sort();

String _set(String name, List<String> codes) =>
    'const Set<String> $name = <String>{\n'
    '${codes.map((c) => "  '$c',\n").join()}'
    '};\n';

void main() {
  final flags = _codesIn('assets/pack_art/flags', '.svg');
  final maps = _codesIn('assets/flag_maps', '.webp');

  final out = File('lib/core/i18n/country_flag_assets.g.dart');
  final header = out.readAsStringSync().split('const Set<String>').first;
  out.writeAsStringSync(
    '$header'
    '${_set('kFlagAssetCodes', flags)}'
    '\n'
    '/// Which alpha-3 codes `assets/flag_maps/` ships a map inset for.\n'
    '///\n'
    '/// A partial, curated set by design — it covers the destinations worth\n'
    '/// illustrating, not the whole catalogue. A code that is absent is a\n'
    '/// finished state, not a gap: the Store card simply draws without one.\n'
    '${_set('kFlagMapCodes', maps)}',
  );
  stdout.writeln(
    '${flags.length} flag codes, ${maps.length} flag-map codes -> ${out.path}',
  );
}

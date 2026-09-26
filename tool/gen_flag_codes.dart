/// Regenerates `lib/core/i18n/country_flag_assets.g.dart` from whatever is
/// actually in `assets/flags/`.
///
/// Run after adding or removing a flag:
///
/// ```
/// dart run tool/gen_flag_codes.dart
/// ```
///
/// The source SVGs come from lipis/flag-icons (`flags/1x1/`, square, meant to
/// be cropped to a circle). Only plain alpha-2 filenames are kept: the
/// upstream set also ships regional blocs (`arab`, `asean`) and subdivisions
/// (`gb-sct`, `es-ct`), which no ISO country code in the catalogue resolves
/// to and which together were a fifth of the bundle.
library;

import 'dart:io';

void main() {
  final dir = Directory('assets/flags');
  final codes = dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.svg'))
      .map((n) => n.substring(0, n.length - 4))
      .where((c) => RegExp(r'^[a-z]{2}$').hasMatch(c))
      .toList()
    ..sort();

  final out = File('lib/core/i18n/country_flag_assets.g.dart');
  final header = out.readAsStringSync().split('const Set<String>').first;
  out.writeAsStringSync(
    '$header'
    'const Set<String> kFlagAssetCodes = <String>{\n'
    '${codes.map((c) => "  '$c',\n").join()}'
    '};\n',
  );
  stdout.writeln('${codes.length} flag codes -> ${out.path}');
}

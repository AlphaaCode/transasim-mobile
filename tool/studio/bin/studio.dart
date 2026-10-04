/// SPC Studio, the local brand builder (docs/STUDIO-SPEC.md).
///
/// ```
/// dart run tool/studio/bin/studio.dart            # serve on 127.0.0.1:4777, open the browser
/// dart run tool/studio/bin/studio.dart --no-open  # serve only
/// dart run tool/studio/bin/studio.dart --check    # validate + golden check every brand, exit 1 on drift
/// ```
///
/// Run from the repo root (tool/studio/studio.bat does). Runs on the plain Dart
/// VM, which is why lib/core/headless.dart exists.
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import '../src/generate.dart';
import '../src/server.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  if (!File('$root/pubspec.yaml').existsSync() || !Directory('$root/brands').existsSync()) {
    stderr.writeln('Run Studio from the repo root (tool/studio/studio.bat does).');
    exit(2);
  }
  if (args.contains('--check')) exit(checkAll(root));
  await serve(root, open: !args.contains('--no-open'));
}

/// Every brand valid, and every generated file what Studio would write.
int checkAll(String root) {
  var failures = 0;
  for (final slug in brandSlugs(root)) {
    final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync())
        as Map<String, dynamic>;
    final v = BrandConfig.parse(brand, expectedSlug: slug);
    final drift = [for (final c in generate(root, slug, brand)) if (c.changed) c.path];
    final ok = v.errors.isEmpty && drift.isEmpty;
    if (!ok) failures++;
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $slug: ${v.errors.length} errors, '
        '${v.warnings.length} warnings, '
        '${drift.isEmpty ? 'generated files in sync' : 'would change ${drift.join(', ')}'}');
    for (final e in v.errors) {
      stdout.writeln('       error $e');
    }
  }
  return failures == 0 ? 0 : 1;
}

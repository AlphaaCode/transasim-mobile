import 'dart:convert';
import 'dart:io';

import '../../tool/studio/src/generate.dart' show generate;

/// A sample brand that is, on purpose, not configured: the brand slug is
/// `acorn` (the backend reports and the tests' ids name it), but its values
/// are frozen in `fixtures/unconfigured/`: a placeholder Stripe key, no
/// Google client, no account deletion form, no upload key, and the DEV
/// backend as its API.
///
/// The tests that assert what an unconfigured brand looks like (the release
/// refusals, the backend items before a client's ids exist) use it instead of
/// `brands/acorn/`, which is the real Acorn and moves on as its ids arrive.
const _dir = 'test/studio/fixtures/unconfigured';

Map<String, dynamic> unconfiguredBrand() =>
    jsonDecode(File('$_dir/brand.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> unconfiguredStudio() =>
    jsonDecode(File('$_dir/studio.json').readAsStringSync()) as Map<String, dynamic>;

/// Writes the sample over `brands/acorn/` (and its xcconfig) in [root], a
/// temporary copy of the repo's text files, then every file Studio generates
/// from it (its flavor bundles, entry points, DEV xcconfig), so the sample
/// root is as Studio would leave it.
void overlayUnconfigured(String root) {
  File('$root/brands/acorn/brand.json').writeAsStringSync(File('$_dir/brand.json').readAsStringSync());
  File('$root/brands/acorn/studio.json').writeAsStringSync(File('$_dir/studio.json').readAsStringSync());
  File('$root/ios/Flutter/acorn.xcconfig').writeAsStringSync(File('$_dir/acorn.xcconfig').readAsStringSync());
  for (final c in generate(root, 'acorn', unconfiguredBrand(), studio: unconfiguredStudio())) {
    if (c.path.endsWith('.json') || c.path.endsWith('.dart') || c.path.endsWith('.xcconfig')) {
      File('$root/${c.path}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(c.after);
    }
  }
}

/// A temporary root with the repo's text files, the sample as `acorn`, and
/// the real sabily and esimple. The caller deletes it.
Directory unconfiguredRoot() {
  final root = Directory.systemTemp.createTempSync('unconfigured');
  final r = root.path.replaceAll(r'\', '/');
  for (final from in ['brands', 'tool/studio/guides', 'tool/studio/templates', 'tool/studio/backend', 'tool/studio/incidents',
      'tool/studio/servers.yaml', 'pubspec.yaml', 'ios/Flutter', 'ios/Runner/Brands', 'android/app/src', 'lib/flavors']) {
    if (FileSystemEntity.typeSync(from) != FileSystemEntityType.directory) {
      File('$r/$from')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(File(from).readAsBytesSync());
      continue;
    }
    for (final f in Directory(from).listSync(recursive: true).whereType<File>()) {
      final rel = f.path.replaceAll(r'\', '/');
      if (rel.endsWith('.png') || rel.endsWith('.mp4') || rel.endsWith('.jpg')) continue;
      File('$r/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(f.readAsBytesSync());
    }
  }
  overlayUnconfigured(r);
  return root;
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's real bundled typefaces into the test binding, so a golden is
/// evidence rather than a picture of Ahem boxes.
///
/// ONE list, read from `pubspec.yaml`, for a reason paid for once: the map used
/// to be copy-pasted into each golden suite, so adding Be Vietnam Pro and IBM
/// Plex Sans left both suites rendering tofu — and because the goldens were
/// regenerated in the same pass, they recorded the tofu and went green.
///
/// Deriving the list from the manifest means a family can only be missing here
/// if it is missing from the app as well.
Future<void> loadRealFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final family in fontFamiliesFromPubspec().entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }
}

/// family -> asset paths, exactly as `pubspec.yaml` declares them.
///
/// Parsed by hand rather than with a YAML package: the shape is two known
/// keys at a fixed indentation, and a dependency to read our own manifest is
/// not worth carrying.
Map<String, List<String>> fontFamiliesFromPubspec() {
  final out = <String, List<String>>{};
  final lines = File('pubspec.yaml').readAsLinesSync();

  var inFonts = false;
  String? family;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#') || trimmed.isEmpty) continue;

    if (trimmed == 'fonts:') {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;

    // Any key back at the `flutter:` child level ends the fonts block.
    if (!line.startsWith('    ') && trimmed.endsWith(':')) break;

    if (trimmed.startsWith('- family:')) {
      family = trimmed.substring('- family:'.length).trim();
      out[family] = <String>[];
    } else if (trimmed.startsWith('- asset:') && family != null) {
      out[family]!.add(trimmed.substring('- asset:'.length).trim());
    }
  }
  return out;
}

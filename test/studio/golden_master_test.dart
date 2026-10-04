import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_brand_flavors.dart' show brandSlugs;
import '../../tool/studio/src/generate.dart';

/// Studio's acceptance test (docs/STUDIO-SPEC.md §12): fed each committed
/// brand.json, the generators reproduce every file Studio owns byte for byte.
/// That is what lets Studio replace the hand work without regressions, and it
/// keeps anyone from hand-editing a generated file: the next regeneration
/// would silently undo it, so the edit fails here instead.
void main() {
  for (final slug in brandSlugs()) {
    group('brands/$slug', () {
      final brand =
          jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
      final generated = generate('.', slug, brand);

      test('regenerating it changes nothing', () {
        final drift = [
          for (final c in generated)
            if (c.changed) '${c.path}\n${unifiedDiff(c.before, c.after)}',
        ];
        expect(drift, isEmpty,
            reason: 'Studio would rewrite these. Edit brand.json or the template under '
                'tool/studio/templates/, never the generated file:\n${drift.join('\n')}');
      });

      test('every text file in its native folders comes from a generator', () {
        // Images are Phase 1b; anything else made by hand is a file a new
        // brand would be missing.
        final owned = {for (final c in generated) c.path};
        final handMade = [
          for (final dir in ['android/app/src/$slug/res', 'ios/Runner/Brands/Brand-$slug.xcassets'])
            for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
              if (!f.path.endsWith('.png')) f.path.replaceAll(r'\', '/'),
        ].where((p) => !owned.contains(p));
        expect(handMade, isEmpty, reason: 'add a template under tool/studio/templates/');
      });
    });
  }
}

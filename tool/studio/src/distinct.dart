/// What no two brands may share. test/core/brand_wiring_test.dart enforces it
/// on the committed folders; Studio checks the same rules before Apply, so a
/// clash is refused in the form instead of failing `flutter test` afterwards.
/// One definition for both.
library;

import 'package:transasim_mobile/core/brand/brand_config.dart' show kKnownRegistrationFields;

/// Fields that identify a client to a store, a phone or a backend: each must
/// be unique across brands.
const kUniqueBrandPaths = [
  'mobile.applicationId',
  'mobile.bundleIdentifier',
  'mobile.deepLinkScheme',
  'mobile.apiBaseUrl',
  'support.email',
];

/// Values any brand may carry because they belong to the socle, not to a
/// client: locale codes, field names, placeholders, and the file names Studio
/// gives every brand's assets.
const kSocleValues = {
  'fr', 'en', 'ar', 'es', 'sl', 'de', 'sq', 'EUR', '1.0.0', //
  'logo-mark.png', 'logo-full.png', 'logo-full-inverse.png', 'logo-intro.mp4',
  'card-background.jpg', '#000000',
  'pk_test_PLACEHOLDER_AWAITING_CLIENT',
  ...kKnownRegistrationFields,
  'account.step.identity', 'account.step.security', 'account.step.details',
};

/// A socle value, or Studio's name for a pack image (`pack-europe.jpg`,
/// `pack-tur.jpg`): two brands may both have a picture of Europe.
bool isSocleValue(String v) => kSocleValues.contains(v) || RegExp(r'^pack-[a-z]+\.jpg$').hasMatch(v);

/// Every string in a brand.json, with the dotted path it was first found at.
Map<String, String> brandValues(Object? json) {
  final out = <String, String>{};
  void walk(Object? node, String path) {
    switch (node) {
      case String s:
        out.putIfAbsent(s, () => path);
      case Map m:
        for (final e in m.entries) {
          walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
        }
      case List l:
        for (final v in l) {
          walk(v, path);
        }
    }
  }

  walk(json, '');
  return out;
}

Object? valueAt(Map json, String path) =>
    path.split('.').fold<Object?>(json, (node, key) => node is Map ? node[key] : null);

/// What [brand] would share with [others] (slug -> brand.json), as
/// field -> reason: a unique field's value, or any non-socle value at all.
Map<String, String> clashes(Map<String, dynamic> brand, Map<String, Map<String, dynamic>> others) {
  final out = <String, String>{};
  final mine = brandValues(brand);
  for (final MapEntry(key: slug, value: other) in others.entries) {
    for (final path in kUniqueBrandPaths) {
      final v = valueAt(brand, path);
      if (v != null && v == valueAt(other, path)) out[path] = '"$v" is already $slug\'s';
    }
    for (final v in brandValues(other).keys) {
      final path = mine[v];
      if (path != null && !isSocleValue(v)) {
        out.putIfAbsent(path, () => '"$v" is $slug\'s value too: a brand value is never shared');
      }
    }
  }
  return out;
}

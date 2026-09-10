import '../brand/brand_config.dart';
import 'strings.dart';

/// String lookup with the brand-override chain.
///
/// ARCHITECTURE-MOBILE.md §2.8. Resolution order, and the reason for each step:
///
///   1. brand override in the REQUESTED language
///   2. brand override in the BRAND'S DEFAULT language
///   3. socle dictionary in the requested language
///   4. socle dictionary in the reference language (en)
///
/// Step 2 is the one people delete by accident. It is deliberate: a brand that
/// translated its own message into only two of six languages is better served
/// by ITS message in the wrong language than by ANOTHER brand's message
/// correctly translated — otherwise both appear on the same screen.
class L10n {
  final BrandConfig brand;
  final String language;

  const L10n({required this.brand, required this.language});

  /// Look up [key], substituting `{placeholders}`.
  ///
  /// `{brand}` is always available and always comes from the config: the brand
  /// name is interpolated, never written into a dictionary (brief §7.1).
  String t(String key, {Map<String, String> vars = const {}}) {
    final template = _resolve(key);
    if (template == null) {
      // A missing key is a socle bug, not a user-facing condition. Surfacing
      // the key beats surfacing an empty string: it is visible in QA.
      assert(false, 'missing i18n key "$key"');
      return key;
    }
    return _interpolate(template, {
      'brand': brand.name,
      'company': brand.legal.displayName,
      'email': brand.support.email,
      ...vars,
    });
  }

  String? _resolve(String key) {
    final override = brand.texts[key];
    if (override != null) {
      final requested = override[language];
      if (requested != null) return requested;
      final brandDefault = override[brand.defaultLocale];
      if (brandDefault != null) return brandDefault;
    }
    return kStrings[language]?[key] ?? kStrings[kReferenceLanguage]?[key];
  }

  static String _interpolate(String template, Map<String, String> vars) {
    if (!template.contains('{')) return template;
    return template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => vars[m.group(1)] ?? m.group(0)!,
    );
  }

  /// Brand text overrides that point at no known key.
  ///
  /// This is the "partially inert configuration" case from brief §2.8 — the
  /// exact situation where a client phones up saying their change was ignored.
  /// Reported as warnings by `tool/check_brands.dart`, never silently dropped.
  static List<String> unknownOverrideKeys(BrandConfig brand) {
    final known = kStrings[kReferenceLanguage]!.keys.toSet();
    return brand.texts.keys.where((k) => !known.contains(k)).toList()..sort();
  }

  /// Keys present in the reference language but missing from [language].
  static List<String> missingKeys(String language) {
    final reference = kStrings[kReferenceLanguage]!.keys.toSet();
    final actual = kStrings[language]?.keys.toSet() ?? <String>{};
    return reference.difference(actual).toList()..sort();
  }
}

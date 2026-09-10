/// Validation outcome for a brand configuration.
///
/// ARCHITECTURE-MOBILE.md §2, §2.10 — two non-negotiable requirements taken
/// from the web contract:
///
///  1. Validation names EVERY problem in one pass, never the first one only.
///     An integrator must fix their config in one go, not in ten.
///  2. It distinguishes an **error** (brand unusable, refused, named in the
///     logs) from a **warning** (brand usable, but part of the configuration
///     is inert). The second case is the one where a client phones up saying
///     their request was ignored.
library;

/// A problem that makes the brand unusable. The brand is refused.
class BrandError {
  /// Dotted path of the offending field, e.g. `colors.primary`, `mobile.apiBaseUrl`.
  final String field;
  final String reason;

  const BrandError(this.field, this.reason);

  @override
  String toString() => '$field: $reason';
}

/// A problem that leaves the brand usable but part of its configuration inert.
class BrandWarning {
  final String field;
  final String reason;

  const BrandWarning(this.field, this.reason);

  @override
  String toString() => '$field: $reason';
}

/// The result of parsing one `brand.json`.
///
/// [config] is non-null if and only if [errors] is empty.
class BrandValidation {
  final Object? config;
  final List<BrandError> errors;
  final List<BrandWarning> warnings;

  const BrandValidation({
    required this.config,
    required this.errors,
    required this.warnings,
  });

  bool get isUsable => errors.isEmpty && config != null;

  /// One-line summary for logs and for `tool/check_brands.dart`.
  String describe(String slug) {
    final b = StringBuffer();
    b.writeln(isUsable ? 'brand "$slug": OK' : 'brand "$slug": REFUSED');
    for (final e in errors) {
      b.writeln('  error   $e');
    }
    for (final w in warnings) {
      b.writeln('  warning $w');
    }
    return b.toString().trimRight();
  }
}

/// Accumulator used while parsing. Collects instead of throwing, so a single
/// pass reports everything.
class BrandProblems {
  final List<BrandError> errors = [];
  final List<BrandWarning> warnings = [];

  void error(String field, String reason) => errors.add(BrandError(field, reason));

  void warn(String field, String reason) => warnings.add(BrandWarning(field, reason));

  bool get hasErrors => errors.isNotEmpty;
}

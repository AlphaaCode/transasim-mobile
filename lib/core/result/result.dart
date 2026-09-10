/// Result and the typed error hierarchy.
///
/// ARCHITECTURE-MOBILE.md §5.2 rule 3: errors are typed and translated at the
/// edge. Nothing in `data/` or `domain/` ever produces a user-facing string —
/// it produces an [AppError] carrying a stable code, and the presentation layer
/// maps that code to a localised message.
///
/// The old app did the opposite: raw exception strings reached the dialog
/// (`ANALYSE-EXISTANT.md` §7.8), so an Arabic-speaking user got an English
/// Stripe SDK message.
library;

/// Success or a typed failure. Dart 3 sealed class — exhaustive `switch`,
/// no `freezed` codegen needed.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  /// The value, or null on failure. Prefer pattern matching over this.
  T? get valueOrNull => switch (this) { Ok<T>(:final value) => value, Err<T>() => null };

  AppError? get errorOrNull => switch (this) { Ok<T>() => null, Err<T>(:final error) => error };
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final AppError error;
  const Err(this.error);
}

/// Every failure the socle can produce, as a closed set.
///
/// [code] is stable and is the l10n key suffix. It never changes with a
/// backend message change — that is the point.
sealed class AppError {
  const AppError();

  /// Stable identifier. Presentation resolves `error.<code>` in the dictionary.
  String get code;

  /// Non-localised detail for logs only. Never shown to a user.
  String? get detail => null;
}

/// No usable connection, DNS failure, or a timeout.
final class NetworkUnavailable extends AppError {
  final String? cause;
  const NetworkUnavailable([this.cause]);
  @override
  String get code => 'network_unavailable';
  @override
  String? get detail => cause;
}

/// The server answered, with a status outside 2xx.
final class HttpFailure extends AppError {
  final int status;

  /// The backend's own error key when it sends one (JHipster sends
  /// `message` / `error`, e.g. `error.idexists`). Used for the few cases where
  /// the socle must branch on a specific server condition.
  final String? serverCode;
  final String? serverMessage;

  const HttpFailure(this.status, {this.serverCode, this.serverMessage});

  @override
  String get code => 'http_$status';
  @override
  String? get detail => serverMessage;

  /// The account already exists. The old app string-matched on
  /// `e.message.contains("error.idexists")`; here it is a named predicate.
  bool get isDuplicateAccount => serverCode == 'error.idexists';
}

/// The response parsed but did not match the contract.
final class ContractViolation extends AppError {
  final String what;
  const ContractViolation(this.what);
  @override
  String get code => 'contract_violation';
  @override
  String? get detail => what;
}

/// The session is gone. The router reacts; screens do not.
final class SessionExpired extends AppError {
  const SessionExpired();
  @override
  String get code => 'session_expired';
}

/// A module's use case was called while its feature flag is off.
///
/// ARCHITECTURE-MOBILE.md §4.2: not registering the route is only half the
/// mechanism. Every optional module's use case starts with its guard and
/// returns this.
final class FeatureUnavailable extends AppError {
  final String moduleId;
  const FeatureUnavailable(this.moduleId);
  @override
  String get code => 'feature_unavailable';
  @override
  String? get detail => moduleId;
}

/// The brand configuration could not be used at all.
final class BrandUnusable extends AppError {
  final List<String> problems;
  const BrandUnusable(this.problems);
  @override
  String get code => 'brand_unusable';
  @override
  String? get detail => problems.join('; ');
}

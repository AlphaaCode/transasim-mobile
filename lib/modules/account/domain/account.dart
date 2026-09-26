/// Account domain. No Flutter, no HTTP — rule L3.
library;

/// A country as the registration form needs it.
class CountryRef {
  final int id;
  final String code;
  final String name;

  /// The country's own language, as the backend records it. Sent back with the
  /// country because `CountryModel` declares it `@NotNull`.
  final String? language;

  const CountryRef({
    required this.id,
    required this.code,
    required this.name,
    this.language,
  });
}

/// Everything a sign-up carries.
///
/// The shape here is still the full nine a person could theoretically fill in
/// — `RegistrationDraft` stays a superset of any one brand's
/// `registration.fields` so the socle has somewhere to put whatever a brand
/// asks for. What's actually REQUIRED is narrower and now confirmed against
/// the live dev backend rather than read off the model's `@NotNull`
/// annotations: see `kServerRequiredRegistrationFields` in
/// `core/brand/brand_config.dart` for the current, tested list and why it no
/// longer matches those eleven annotations.
class RegistrationDraft {
  final String email;
  final String password;
  final String firstName;
  final String lastName;

  /// `LocalDate` server-side, so it serialises as YYYY-MM-DD.
  final DateTime? dateOfBirth;

  final String address;
  final String zipCode;
  final String city;
  final CountryRef? country;

  /// Optional server-side — the only one of the visible fields that is.
  final String phoneNum;

  const RegistrationDraft({
    this.email = '',
    this.password = '',
    this.firstName = '',
    this.lastName = '',
    this.dateOfBirth,
    this.address = '',
    this.zipCode = '',
    this.city = '',
    this.country,
    this.phoneNum = '',
  });

  RegistrationDraft copyWith({
    String? email,
    String? password,
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    String? address,
    String? zipCode,
    String? city,
    CountryRef? country,
    String? phoneNum,
  }) =>
      RegistrationDraft(
        email: email ?? this.email,
        password: password ?? this.password,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        address: address ?? this.address,
        zipCode: zipCode ?? this.zipCode,
        city: city ?? this.city,
        country: country ?? this.country,
        phoneNum: phoneNum ?? this.phoneNum,
      );

  /// Read one field by its configured id, so the form can be driven by
  /// `registration.fields` without a switch in every widget.
  String? valueOf(String fieldId) => switch (fieldId) {
        'email' => email,
        'password' => password,
        'firstName' => firstName,
        'lastName' => lastName,
        'dateOfBirth' => dateOfBirth == null ? '' : formatDate(dateOfBirth!),
        'address' => address,
        'zipCode' => zipCode,
        'city' => city,
        'country' => country?.name ?? '',
        'phoneNum' => phoneNum,
        _ => null,
      };

  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// The signed-in user, as `GET /account` describes them.
///
/// ⚠️ The wire `Subscriber` carries a `password` field — `api-contract.md` §2
/// flags it as a defect to fix server-side. It is deliberately not modelled
/// here: nothing in this app should be able to read it, even by accident.
class Profile {
  final int? id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phoneNum;
  final String? city;
  final String? country;

  const Profile({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phoneNum,
    this.city,
    this.country,
  });

  String get displayName {
    final parts = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? email : parts.join(' ');
  }

  String get initials {
    final f = (firstName ?? '').trim();
    final l = (lastName ?? '').trim();
    if (f.isEmpty && l.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    return '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}'.toUpperCase();
  }
}

/// What the presentation layer asks for.
abstract class AccountRepository {
  /// Returns the raw JWT on success. The caller hands it to the session; this
  /// contract never persists anything itself.
  Future<String> signIn({required String email, required String password});

  /// Exchanges a provider ID token for the same JWT [signIn] returns. The
  /// provider SDKs are never reached from here: the caller obtains the ID
  /// token and hands it over, so this contract stays HTTP-only and testable
  /// without a Google or Apple account.
  Future<String> signInWithGoogle(String idToken);

  Future<String> signInWithApple(String idToken);

  /// Creates the account. The server then emails a one-time code; it does NOT
  /// return a token, so registration is always followed by verification.
  Future<void> register(RegistrationDraft draft, {required String language});

  /// Confirms the one-time code. Returns a JWT when the server issues one.
  Future<String?> verify({required String email, required String code});

  Future<void> resendCode(String email);

  Future<void> requestPasswordReset(String email);

  /// Sets a new password with the code the reset email carried.
  Future<void> finishPasswordReset({required String code, required String newPassword});

  Future<Profile> profile();

  /// Countries for the registration picker.
  Future<List<CountryRef>> countries();
}

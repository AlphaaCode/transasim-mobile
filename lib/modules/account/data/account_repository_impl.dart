import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/account.dart';

/// Talks to the JHipster backend. Endpoint shapes from `api-contract.md` §1–§2,
/// re-checked against the deployed JAR rather than taken on trust.
///
/// Paths are relative to the brand's `apiBaseUrl`, which already ends in `/api`.
class AccountRepositoryImpl implements AccountRepository {
  final ApiClient _api;

  AccountRepositoryImpl(this._api);

  /// A1 — `POST /api/authenticate` -> `{ id_token }`.
  ///
  /// The response is the JHipster `JWTToken` DTO and carries `id_token` ONLY.
  /// The old client also read `json['user']` and defaulted it to `{}`; that key
  /// does not exist on the deployed DTO, so every consumer of it was reading
  /// nothing (`ANALYSE-EXISTANT.md` §7.10).
  @override
  Future<String> signIn({required String email, required String password}) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/authenticate',
      body: {'username': email, 'password': password},
      auth: false,
    );
    return _idToken(_require(result), 'authenticate');
  }

  /// A7 — `POST /api/v1/auth/google`, body `{ idToken }`.
  /// A8 — `POST /api/v1/auth/apple`, the same shape.
  ///
  /// Both answer with the same `JWTToken` DTO as A1, so the token is read by
  /// the same check and stored by the same caller — a social sign-in is the
  /// email path with a different first step, not a second session mechanism.
  ///
  /// ⚠️ Live on 22/09/2026: a junk token gets 401 `invalid-social-token`, which
  /// proves the routes exist and validate. What is NOT proven is that the JWT
  /// issued for a real Google or Apple account carries everything
  /// `/authenticate`'s does. Hence the same permissive check rather than a
  /// stricter one: if the server says it issued a token, this believes it, and
  /// anything missing surfaces on the first authenticated call instead of
  /// being second-guessed here.
  ///
  /// The legacy `/api/google-auth`, `/api/apple-auth` and their `-register`
  /// twins still answer on this backend. They belong to the previous app and
  /// are deliberately not used.
  @override
  Future<String> signInWithGoogle(String idToken) => _social('/v1/auth/google', idToken);

  @override
  Future<String> signInWithApple(String idToken) => _social('/v1/auth/apple', idToken);

  Future<String> _social(String path, String idToken) async {
    final result = await _api.post<Map<String, dynamic>>(
      path,
      body: {'idToken': idToken},
      auth: false,
    );
    return _idToken(_require(result), path);
  }

  /// The one reading of `JWTToken`, shared by every route that issues one.
  String _idToken(Map<String, dynamic> body, String endpoint) {
    final token = body['id_token'];
    if (token is! String || token.isEmpty) {
      // The old client stored an empty string here and treated it as a session.
      throw AccountFailure(ContractViolation('$endpoint returned no id_token'));
    }
    return token;
  }

  /// A2 — `POST /api/v1/subscribers/register`.
  ///
  /// Sends all eleven `@NotNull` fields. Three are supplied here rather than
  /// typed by the user:
  ///
  ///  - `language`  — the interface language in use;
  ///  - `platform`  — optional server-side, sent anyway so support can tell
  ///                  where a sign-up came from;
  ///  - `title`     — a salutation nobody is asked for. The LIVE app sends
  ///                  `null`, which the deployed `@NotNull` should reject; an
  ///                  empty string satisfies the constraint under either
  ///                  reading, so that is what goes. Raised as a backend
  ///                  question rather than guessed at.
  @override
  Future<void> register(RegistrationDraft draft, {required String language}) async {
    final country = draft.country;
    final result = await _api.post<dynamic>(
      '/v1/subscribers/register',
      auth: false,
      body: <String, dynamic>{
        'title': '',
        'email': draft.email,
        'firstName': draft.firstName,
        'lastName': draft.lastName,
        'dateOfBirth':
            draft.dateOfBirth == null ? null : RegistrationDraft.formatDate(draft.dateOfBirth!),
        'address': draft.address,
        'zipCode': draft.zipCode,
        'city': draft.city,
        'phoneNum': draft.phoneNum,
        'language': language,
        // `CountryModel` declares `code` and `language` @NotNull. Nested
        // validation does not cascade without @Valid, so `{id}` alone is
        // probably accepted — but all three come from the same response, so
        // sending them costs nothing and is correct under either reading.
        'country': country == null
            ? null
            : {
                'id': country.id,
                'code': country.code,
                if (country.language != null) 'language': country.language,
              },
        'password': draft.password,
        'platform': 'ANDROID',
      },
    );
    _require(result);
  }

  /// A3 — `PUT /api/v1/subscribers/account/activate?key=&email=`.
  ///
  /// NOT the path the old client used. It called `GET /api/activate?key=`, the
  /// stock JHipster route; the deployed extended resource is a PUT that also
  /// takes the email, which is what ties a code to an account.
  ///
  /// ⚠️ The code still travels in a query string, so it lands in access logs
  /// and in any intermediary proxy log. That is a backend request, unchanged
  /// from `api-contract.md` §9 — the client cannot fix it by itself.
  @override
  Future<String?> verify({required String email, required String code}) async {
    // PUT. Live `Allow: PUT,OPTIONS`; POST is a 405, and the controller used to
    // read that 405 as "this code is not valid", so activation from the app
    // could never succeed while looking like the user's mistake.
    final result = await _api.put<dynamic>(
      '/v1/subscribers/account/activate',
      auth: false,
      query: {'key': code, 'email': email, 'platform': 'ANDROID'},
    );
    final body = _require(result);
    if (body is Map && body['id_token'] is String) return body['id_token'] as String;
    // Activation may succeed without issuing a token; the caller then signs in.
    return null;
  }

  /// A4 — `POST /api/v1/subscribers/resend-otp?login={email}`.
  @override
  Future<void> resendCode(String email) async {
    _require(await _api.post<dynamic>(
      '/v1/subscribers/resend-otp',
      auth: false,
      query: {'login': email},
    ));
  }

  /// A5 — `POST /api/account/reset-password/init`, body is a BARE STRING.
  @override
  Future<void> requestPasswordReset(String email) async {
    _require(await _api.post<dynamic>(
      '/account/reset-password/init',
      auth: false,
      body: email,
    ));
  }

  /// A6 — `POST /api/account/reset-password/finish`, `{key, newPassword}`
  /// (`KeyAndPasswordVM`). `key` is the 6-character code from the email.
  ///
  /// Checked live: a password the server refuses is a 400 of type
  /// `invalid-password`, tested BEFORE the key; an unknown key is a 500
  /// "No user was found for this reset key".
  @override
  Future<void> finishPasswordReset({required String code, required String newPassword}) async {
    _require(await _api.post<dynamic>(
      '/account/reset-password/finish',
      auth: false,
      body: <String, dynamic>{'key': code, 'newPassword': newPassword},
    ));
  }

  /// P1 — `GET /api/account`.
  @override
  Future<Profile> profile() async {
    final body = _require(await _api.get<Map<String, dynamic>>('/account'));
    return Profile(
      id: body['id'] is num ? (body['id'] as num).toInt() : null,
      email: body['email']?.toString() ?? '',
      firstName: body['firstName']?.toString(),
      lastName: body['lastName']?.toString(),
      phoneNum: body['phoneNum']?.toString(),
      city: body['city']?.toString(),
      country: body['country'] is Map
          ? (body['country'] as Map)['country']?.toString()
          : body['country']?.toString(),
      // `password` is deliberately not read. See Profile.
    );
  }

  /// C2 — `GET /api/v1/countries/all`, public.
  ///
  /// Fetched here rather than borrowed from the catalogue module: a module may
  /// not import another (rule L2), and one shared HTTP call is cheaper than an
  /// abstraction nothing else needs yet.
  @override
  Future<List<CountryRef>> countries() async {
    final rows = _require(await _api.get<List<dynamic>>('/v1/countries/all', auth: false));
    final out = <CountryRef>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = row['id'];
      final code = row['code']?.toString();
      final name = (row['name'] ?? row['country'])?.toString();
      if (id is! num || code == null || name == null) continue;
      out.add(CountryRef(
        id: id.toInt(),
        code: code,
        name: name,
        language: row['language']?.toString(),
      ));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  T _require<T>(Result<T> result) => switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw AccountFailure(error),
      };
}

/// Carries a typed [AppError] out of the repository, so the controller can
/// translate it at the edge instead of surfacing an exception string.
class AccountFailure implements Exception {
  final AppError error;
  const AccountFailure(this.error);

  /// The account already exists. The old app matched on a substring of the
  /// server message; here the server's own error key is compared.
  bool get isDuplicateAccount {
    final e = error;
    return e is HttpFailure && e.isDuplicateAccount;
  }

  /// The reset code matches no account (live: 500, "No user was found for
  /// this reset key"). Matched on that detail, because a bare 500 can also be
  /// the server failing, and that must not read as "your code is wrong".
  bool get isUnknownResetCode {
    final e = error;
    return e is HttpFailure && (e.serverMessage ?? '').contains('reset key');
  }

  /// The server refused the new password (live: 400, type invalid-password).
  bool get isPasswordRejected {
    final e = error;
    return e is HttpFailure && (e.serverMessage ?? '').contains('invalid-password');
  }

  /// Wrong email or password. JHipster answers 401 on a bad credential, which
  /// the network layer maps to SessionExpired — correct for an expired token,
  /// misleading during sign-in, so sign-in reads it as bad credentials.
  bool get isBadCredentials => error is SessionExpired;

  @override
  String toString() => 'AccountFailure(${error.code})';
}
